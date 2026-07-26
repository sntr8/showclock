import Foundation
import Darwin

// Communicates with QLab via its OSC workspace API over UDP.
// Binds to listenPort so QLab replies arrive on the same socket we send from.
class QLabManager: ObservableObject {
    @Published var nextCueName: String? = nil
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Not connected"

    private(set) var host: String = "127.0.0.1"
    private(set) var port: UInt16 = 53000
    private let listenPort: UInt16 = 53001

    private var socketFd: Int32 = -1
    private var receiveThread: Thread?
    private var running = false
    private var pollTimer: Timer?
    private var workspaceID: String?

    // MARK: - Lifecycle

    func start(host: String, port: Int) {
        stop()
        self.host = host
        self.port = UInt16(port)

        socketFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFd >= 0 else {
            setStatus("Socket error")
            return
        }

        var yes: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = listenPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                bind(socketFd, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            setStatus("Failed to bind port \(listenPort)")
            Darwin.close(socketFd)
            socketFd = -1
            return
        }

        running = true
        receiveThread = Thread { [weak self] in self?.receiveLoop() }
        receiveThread?.start()

        sendOSC("/workspaces")
        setStatus("Connecting...")
    }

    func stop() {
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        if socketFd >= 0 {
            Darwin.close(socketFd)
            socketFd = -1
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.workspaceID = nil
            self.nextCueName = nil
            self.statusMessage = "Not connected"
        }
    }

    // MARK: - Polling

    private func startPolling() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, let wid = self.workspaceID else { return }
                self.sendOSC("/workspace/\(wid)/selectedCues")
            }
        }
    }

    // MARK: - UDP send

    private func sendOSC(_ address: String) {
        guard socketFd >= 0 else { return }
        let msg = buildOSCMessage(address: address)
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        dest.sin_addr.s_addr = inet_addr(host)
        _ = msg.withUnsafeBytes { raw in
            withUnsafePointer(to: &dest) { dp in
                dp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    sendto(socketFd, raw.baseAddress, msg.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while running && socketFd >= 0 {
            let n = recv(socketFd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            let data = Data(buffer[0..<n])
            handleIncoming(data)
        }
    }

    private func handleIncoming(_ data: Data) {
        guard let (address, args) = parseOSCMessage(data) else { return }
        guard address == "/reply", args.count >= 2 else { return }
        let query = args[0]
        let json = args[1]
        dispatchReply(query: query, json: json)
    }

    private func dispatchReply(query: String, json: String) {
        guard let raw = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              (obj["status"] as? String) == "ok" else { return }

        if query == "/workspaces" {
            guard let list = obj["data"] as? [[String: Any]],
                  let first = list.first,
                  let wid = first["uniqueID"] as? String else {
                setStatus("No workspaces found")
                return
            }
            workspaceID = wid
            let wsName = (first["displayName"] as? String) ?? wid
            sendOSC("/workspace/\(wid)/connect")
            setStatus("Connected: \(wsName)")
            DispatchQueue.main.async { self.isConnected = true }
            startPolling()

        } else if query.hasSuffix("/connect") {
            // acknowledged — polling already started above

        } else if query.hasSuffix("/selectedCues") {
            let cues = obj["data"] as? [[String: Any]]
            let name = cues?.first.flatMap { c in
                (c["displayName"] as? String) ?? (c["name"] as? String) ?? (c["number"] as? String)
            }
            DispatchQueue.main.async { self.nextCueName = name }
        }
    }

    // MARK: - OSC helpers

    private func buildOSCMessage(address: String) -> Data {
        var data = Data()
        data.append(oscPaddedString(address))
        data.append(oscPaddedString(","))
        return data
    }

    private func oscPaddedString(_ s: String) -> Data {
        var bytes = Array(s.utf8) + [0]
        let target = ((bytes.count + 3) / 4) * 4
        while bytes.count < target { bytes.append(0) }
        return Data(bytes)
    }

    private func parseOSCMessage(_ data: Data) -> (String, [String])? {
        var offset = 0
        guard let address = readOSCString(data, offset: &offset) else { return nil }
        guard let typeTags = readOSCString(data, offset: &offset) else { return nil }

        var strings: [String] = []
        for tag in typeTags.dropFirst() {
            switch tag {
            case "s":
                if let s = readOSCString(data, offset: &offset) { strings.append(s) }
            case "i", "f":
                offset += 4
            case "d", "h", "t":
                offset += 8
            default:
                break
            }
        }
        return (address, strings)
    }

    private func readOSCString(_ data: Data, offset: inout Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 { end += 1 }
        let str = String(bytes: data[offset..<end], encoding: .utf8)
        offset = end + 1
        offset = ((offset + 3) / 4) * 4
        return str
    }

    // MARK: - Helpers

    private func setStatus(_ msg: String) {
        DispatchQueue.main.async { self.statusMessage = msg }
    }
}
