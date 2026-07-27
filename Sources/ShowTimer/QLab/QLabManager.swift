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
    private var workspaceName: String?
    private var passcode: String = ""

    // MARK: - Lifecycle

    func start(host: String, port: Int, passcode: String = "") {
        stop()
        self.host = host
        self.port = UInt16(port)
        self.passcode = passcode

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
        // Not @Published, so no need to hop to main — and it must not be
        // deferred: start() calls stop() then immediately reconnects, and a
        // queued async reset here would otherwise land *after* the new
        // connection sets a fresh workspaceID, wiping it back to nil right
        // before the poll timer's first tick ever fires.
        workspaceID = nil
        if socketFd >= 0 {
            Darwin.close(socketFd)
            socketFd = -1
        }
        DispatchQueue.main.async {
            self.isConnected = false
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

    private func sendOSC(_ address: String, stringArg: String? = nil) {
        guard socketFd >= 0 else { return }
        let msg = buildOSCMessage(address: address, stringArg: stringArg)
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
        // QLab replies land on "/reply" + the original address, e.g. "/reply/workspaces",
        // with a single JSON string argument (not "/reply" with the path as an arg).
        guard address.hasPrefix("/reply/"), let json = args.first else { return }
        let query = String(address.dropFirst("/reply".count))
        dispatchReply(query: query, json: json)
    }

    private func dispatchReply(query: String, json: String) {
        guard let raw = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return }
        let ok = (obj["status"] as? String) == "ok"

        if query == "/workspaces" {
            guard ok, let list = obj["data"] as? [[String: Any]],
                  let first = list.first,
                  let wid = first["uniqueID"] as? String else {
                setStatus("No workspaces found")
                return
            }
            // dispatchReply runs on the background receive thread; hop to
            // main before touching workspaceID since it's also read/written
            // from the main-thread poll timer and stop().
            DispatchQueue.main.async { self.workspaceID = wid }
            workspaceName = (first["displayName"] as? String) ?? wid
            // Don't report connected yet: QLab requires a passcode (if the
            // workspace has one set) before it accepts anything else, and a
            // failed /connect here would otherwise leave us silently polling
            // into the void while still showing a green "connected" dot.
            sendOSC("/workspace/\(wid)/connect", stringArg: passcode.isEmpty ? nil : passcode)

        } else if query.hasSuffix("/connect") {
            guard ok else {
                setStatus("QLab rejected connection — check passcode")
                return
            }
            setStatus("Connected: \(workspaceName ?? workspaceID ?? "")")
            DispatchQueue.main.async { self.isConnected = true }
            startPolling()

        } else if query.hasSuffix("/selectedCues") {
            guard ok else { return }
            let cues = obj["data"] as? [[String: Any]]
            // "listName" is the label QLab actually shows in its cue list (number + name);
            // "name" is just the custom name and is often an empty string, which would
            // otherwise win here and render as a blank "Next: " with nothing after it.
            let name = cues?.first.flatMap { c -> String? in
                if let listName = c["listName"] as? String, !listName.isEmpty { return listName }
                if let n = c["name"] as? String, !n.isEmpty { return n }
                return c["number"] as? String
            }
            DispatchQueue.main.async { self.nextCueName = name }
        }
    }

    // MARK: - OSC helpers

    private func buildOSCMessage(address: String, stringArg: String? = nil) -> Data {
        var data = Data()
        data.append(oscPaddedString(address))
        if let stringArg {
            data.append(oscPaddedString(",s"))
            data.append(oscPaddedString(stringArg))
        } else {
            data.append(oscPaddedString(","))
        }
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
