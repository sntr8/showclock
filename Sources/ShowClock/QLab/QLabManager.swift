import Foundation
import Darwin

// Communicates with QLab via its OSC workspace API over UDP.
// Binds to listenPort so QLab replies arrive on the same socket we send from.
class QLabManager: ObservableObject {
    @Published var nextCueName: String? = nil
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Not connected"
    // Whether QLab currently has any cue running or paused — used to decide
    // when overtime is actually "over" rather than just a fixed timeout.
    @Published var hasActiveCues: Bool = false
    // Summed remaining playback time (seconds) of the current cue plus every
    // armed, playable (Audio/Video/Mic) cue still ahead of it in the cue
    // list — lets the operator see in Settings whether the show is tracking
    // to run long, independent of anything shown on the clock itself.
    @Published var totalRemainingSeconds: Double? = nil
    // When totalRemainingSeconds most recently dropped to (about) zero, or
    // nil while it's still above zero / unknown. AppSettings.isShowingPlainClock
    // uses this to hold the overtime countdown on screen for a short grace
    // period after QLab says the show is done, instead of cutting to the
    // plain clock the instant it does.
    @Published private(set) var remainingReachedZeroAt: Date? = nil

    private(set) var host: String = "127.0.0.1"
    private(set) var port: UInt16 = 53000
    private var listenPort: UInt16 = 53001

    private var socketFd: Int32 = -1
    private var receiveThread: Thread?
    private var running = false
    private var pollTimer: Timer?
    private var workspaceID: String?
    private var workspaceName: String?
    private var passcode: String = ""
    // Per-cue tracking, all keyed by uniqueID. Populated from the receive
    // thread (dispatchReply's call stack); reset from the main thread by
    // stop()/markDisconnected(). No explicit synchronization — same
    // pragmatic tolerance as elsewhere in this class: a stale read during
    // the brief reset window just means a momentarily-wrong cache entry, not
    // a crash, and these values only ever move from real state to zeroed.
    private var activeCueElapsed: [String: Double] = [:]  // currently-playing cues only
    private var cueDuration: [String: Double] = [:]        // permanent once known; doesn't change
    private var cueType: [String: String] = [:]            // permanent once known
    private var cueArmed: [String: Bool] = [:]             // refreshed each poll; can change live
    private var cueOrder: [String] = []                    // flattened leaf IDs, show order
    private var cueIndexForID: [String: Int] = [:]         // leaf id -> index in cueOrder; Group ids map to their first descendant leaf's index
    // leaf id -> every containing cue's id, nearest first (immediate parent,
    // then grandparent, ... up to the containing cue list). A Timeline group
    // (see cueMode below) is often built from tracks each individually
    // wrapped in their own sub-Group (e.g. for per-track fades) — so two
    // leaves that genuinely start together can have *different* immediate
    // parents, with their nearest shared Timeline ancestor several levels
    // up. This field's first shipped version only recorded the immediate
    // parent, so a Timeline group built that way still had every track
    // summed independently — walking the whole chain in
    // timelineClusterRoot(for:) is what actually fixes it.
    private var ancestorChain: [String: [String]] = [:]
    // permanent once known; a Group cue's playback mode (0=List, 1=Start
    // first and enter, 2=Start first, 3=Timeline, 4=Start random, 5=Cart,
    // 6=Playlist — see QLab's OSC dictionary). Only mode 3 (Timeline) starts
    // every child simultaneously; that's the "one cue, multiple tracks"
    // case (e.g. stereo stems or multitrack backing files grouped together)
    // that recomputeTotalRemaining needs to sum once, not per track.
    private var cueMode: [String: Int] = [:]
    private static let timelineGroupMode = 3
    // permanent once known; per-cue continueMode (0=Do Not Continue,
    // 1=Auto-continue, 2=Auto-follow — see QLab's OSC dictionary). QLab's
    // *other* way (besides a Timeline Group) to build a "several tracks, one
    // Go press" cue: flat sibling cues in the list, each wired with
    // Auto-continue, no Group involved at all. Auto-continue on a cue means
    // the very next leaf in cueOrder starts essentially at the same moment
    // this one does (Auto-follow, by contrast, waits for this cue to finish
    // first — genuinely sequential, not simultaneous, so it's excluded).
    private var cueContinueMode: [String: Int] = [:]
    private static let autoContinueMode = 1
    private var selectedCueID: String?
    // Set the first time currentStartIndex finds a real selected/active cue
    // position after connecting; see its use there for why this matters.
    private var hasSeenCuePosition = false
    // UDP has no disconnect signal — quitting QLab looks identical to a
    // silent network hiccup, so the only way to notice is a watchdog: if
    // nothing at all has arrived in a while, assume it's gone.
    private var lastReplyAt: Date?
    private static let disconnectTimeout: TimeInterval = 5
    // Coalesces recomputation to once per poll tick regardless of how many
    // cue-level replies arrive in between — see the note at
    // remainingNeedsRecompute's use site for what happens without this.
    private var remainingNeedsRecompute = false
    private var pollTickCount = 0
    // cueLists/uniqueIDs + a fresh /armed query for every cue used to run
    // every single 1-second tick. For a real show's cue count (386 in
    // testing) that's 386+ UDP sends and a similar flood of replies *every
    // second*, each one triggering a full recompute — measured at ~40% CPU
    // and ~500KB/s resident memory growth just sitting idle. The cue list's
    // structure and armed state don't need per-second freshness (cues aren't
    // added/removed live, and an operator arming/disarming something is a
    // rare, deliberate act) — every 10s is still prompt for a human-facing
    // "might run over" warning, at a tenth of the traffic.
    private static let structureRefreshEveryNTicks = 10

    // MARK: - Lifecycle

    func start(host: String, port: Int, passcode: String = "", replyPort: UInt16 = 53001) {
        stop()
        self.host = host
        self.port = UInt16(port)
        self.passcode = passcode
        self.listenPort = replyPort

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

        setStatus("Connecting...")
        sendOSC("/workspaces")
        // Not just that one-shot send above: a single UDP packet has no
        // retry if it's lost (e.g. QLab's OSC listener isn't fully up yet at
        // the exact moment the app launches), and nothing else was ever
        // going to resend it — this was the connect-on-launch bug where it
        // sat stuck on "Connecting..." until a manual Connect click sent a
        // fresh one. startPolling() already knows to keep retrying
        // /workspaces for as long as there's no workspace, so start it now
        // too as the retry safety net.
        startPolling()
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
        activeCueElapsed = [:]
        cueDuration = [:]
        cueType = [:]
        cueArmed = [:]
        cueOrder = []
        cueIndexForID = [:]
        ancestorChain = [:]
        cueMode = [:]
        cueContinueMode = [:]
        selectedCueID = nil
        hasSeenCuePosition = false
        lastReplyAt = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.nextCueName = nil
            self.hasActiveCues = false
            self.totalRemainingSeconds = nil
            self.remainingReachedZeroAt = nil
            self.statusMessage = "Not connected"
        }
    }

    // MARK: - Polling

    private func startPolling() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }

                if self.isConnected, let last = self.lastReplyAt,
                   Date().timeIntervalSince(last) > Self.disconnectTimeout {
                    self.markDisconnected()
                }

                if let wid = self.workspaceID {
                    self.sendOSC("/workspace/\(wid)/selectedCues")
                    self.sendOSC("/workspace/\(wid)/runningOrPausedCues")
                    self.pollTickCount += 1
                    if self.pollTickCount % Self.structureRefreshEveryNTicks == 1 {
                        self.sendOSC("/workspace/\(wid)/cueLists/uniqueIDs")
                    }
                } else {
                    // No workspace (never found one, or just lost the
                    // connection above) — keep retrying discovery so a
                    // relaunched QLab gets picked back up automatically.
                    self.sendOSC("/workspaces")
                }

                // Coalesced here, not from each cue-level reply handler: with
                // hundreds of cues in flight at once, recomputing (and
                // dispatching to main) on every single one was the flood
                // above. One recompute per tick is all a human-facing number
                // needs.
                if self.remainingNeedsRecompute {
                    self.remainingNeedsRecompute = false
                    self.recomputeTotalRemaining()
                }
            }
        }
    }

    private func markDisconnected() {
        workspaceID = nil
        cueOrder = []
        cueIndexForID = [:]
        ancestorChain = [:]
        cueMode = [:]
        cueContinueMode = [:]
        activeCueElapsed = [:]
        cueType = [:]
        cueDuration = [:]
        cueArmed = [:]
        selectedCueID = nil
        hasSeenCuePosition = false
        DispatchQueue.main.async {
            self.isConnected = false
            self.nextCueName = nil
            self.hasActiveCues = false
            self.totalRemainingSeconds = nil
            self.remainingReachedZeroAt = nil
            self.statusMessage = "Connection lost"
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
        // dispatchReply (and everything it touches: cueOrder, cueDuration,
        // cueType, cueArmed, activeCueElapsed, cueIndexForID, selectedCueID,
        // lastReplyAt) must run on the same thread that reads them — the
        // main-thread poll timer's recomputeTotalRemaining()/
        // currentStartIndex(). This used to run inline on receiveLoop's
        // background thread instead, racing unsynchronized against those
        // main-thread reads on plain Swift Array/Dictionary storage — not a
        // narrow bug, genuine heap corruption (concurrent mutation of Swift
        // collections without synchronization is undefined behavior), which
        // surfaced as crashes in unrelated-looking places (different
        // objc_release call sites each time, whenever the corrupted memory
        // later happened to get deallocated).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastReplyAt = Date()
            self.dispatchReply(query: query, json: json)
        }
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
            // Polling is already running continuously since start() — it
            // began retrying /workspaces before we even had a workspace, and
            // seamlessly switches to full polling now that we have one.

        } else if query.hasSuffix("/selectedCues") {
            guard ok else { return }
            let cues = obj["data"] as? [[String: Any]]
            selectedCueID = cues?.first?["uniqueID"] as? String
            // "listName" is the label QLab actually shows in its cue list (number + name);
            // "name" is just the custom name and is often an empty string, which would
            // otherwise win here and render as a blank "Next: " with nothing after it.
            let name = cues?.first.flatMap { c -> String? in
                // A disarmed cue won't actually fire on Go, so showing it as
                // "Next" is misleading — QLab still reports it as selected
                // even while disarmed.
                guard isCueArmed(c) else { return nil }
                if let listName = c["listName"] as? String, !listName.isEmpty { return listName }
                if let n = c["name"] as? String, !n.isEmpty { return n }
                return c["number"] as? String
            }
            DispatchQueue.main.async { self.nextCueName = name }
            remainingNeedsRecompute = true

        } else if query.hasSuffix("/runningOrPausedCues") {
            guard ok else { return }
            let cues = obj["data"] as? [[String: Any]] ?? []
            DispatchQueue.main.async { self.hasActiveCues = !cues.isEmpty }

            // runningOrPausedCues nests Group cues around their children;
            // only leaves (no "cues" of their own) are actual playable audio/
            // video cues with a real elapsed/duration to query.
            let leafIDs = Self.flattenRunningLeafCueIDs(cues)
            activeCueElapsed = activeCueElapsed.filter { leafIDs.contains($0.key) }
            for id in leafIDs {
                sendOSC("/cue_id/\(id)/actionElapsed")
                sendOSC("/cue_id/\(id)/duration")
            }
            remainingNeedsRecompute = true

        } else if query.hasSuffix("/cueLists/uniqueIDs") {
            guard ok, let list = obj["data"] as? [[String: Any]] else { return }
            let (order, indexForID, chains) = Self.buildCueOrder(list)
            cueOrder = order
            cueIndexForID = indexForID
            ancestorChain = chains
            // Cues before the current position can never contribute to
            // recomputeTotalRemaining's sum (it only walks from startIndex
            // onward), so there's no reason to fetch or re-check their
            // static info or armed state at all — for a show partway
            // through, that's a real cut to an already-reduced burst, not
            // just the once-per-cue caching this already had.
            if !order.isEmpty {
                let startIndex = currentStartIndex(in: order, indexForID: indexForID)
                for id in order[startIndex...] {
                    if cueType[id] == nil { sendOSC("/cue_id/\(id)/type") }
                    if cueDuration[id] == nil { sendOSC("/cue_id/\(id)/duration") }
                    if cueContinueMode[id] == nil { sendOSC("/cue_id/\(id)/continueMode") }
                    sendOSC("/cue_id/\(id)/armed")
                }
                // Need every relevant leaf's *entire* ancestor chain's mode,
                // not just its immediate parent's — see ancestorChain's
                // declaration for why a Timeline group's own children can be
                // wrapper Groups rather than the leaves themselves.
                let relevantAncestors = Set(order[startIndex...].flatMap { chains[$0] ?? [] })
                for id in relevantAncestors where cueMode[id] == nil {
                    sendOSC("/cue_id/\(id)/mode")
                }
            }
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/actionElapsed") {
            guard ok, let elapsed = obj["data"] as? Double, let id = Self.cueID(fromQuery: query) else { return }
            activeCueElapsed[id] = elapsed
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/duration") {
            guard ok, let duration = obj["data"] as? Double, let id = Self.cueID(fromQuery: query) else { return }
            cueDuration[id] = duration
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/type") {
            guard ok, let type = obj["data"] as? String, let id = Self.cueID(fromQuery: query) else { return }
            cueType[id] = type
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/armed") {
            guard ok, let id = Self.cueID(fromQuery: query) else { return }
            if let b = obj["data"] as? Bool { cueArmed[id] = b }
            else if let n = obj["data"] as? Int { cueArmed[id] = n != 0 }
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/mode") {
            guard ok, let id = Self.cueID(fromQuery: query) else { return }
            if let m = obj["data"] as? Int { cueMode[id] = m }
            else if let m = obj["data"] as? Double { cueMode[id] = Int(m) }
            remainingNeedsRecompute = true

        } else if query.hasPrefix("/cue_id/") && query.hasSuffix("/continueMode") {
            guard ok, let id = Self.cueID(fromQuery: query) else { return }
            if let m = obj["data"] as? Int { cueContinueMode[id] = m }
            else if let m = obj["data"] as? Double { cueContinueMode[id] = Int(m) }
            remainingNeedsRecompute = true
        }
    }

    private static let playableCueTypes: Set<String> = ["Audio", "Video", "Mic"]

    // Not just selectedCueID's index: QLab typically advances the playhead
    // to the *next* cue immediately on Go, before the cue that just fired has
    // finished playing — so the selected cue can already be one step ahead of
    // what's still actually audible. Starting only from there would skip the
    // currently-playing cue's own shrinking remaining time entirely, which is
    // why the total wasn't ticking down while something was running. Back up
    // to the earliest of the selected position or any cue actually known to
    // be playing. Shared between recomputeTotalRemaining and the
    // cueLists/uniqueIDs handler, which uses it to skip fetching info for
    // cues that have already played and can never contribute to the sum.
    private func currentStartIndex(in order: [String], indexForID: [String: Int]) -> Int {
        guard !order.isEmpty else { return 0 }
        let selectedIndex = selectedCueID.flatMap { indexForID[$0] }
        let activeIndices = activeCueElapsed.keys.compactMap { indexForID[$0] }
        if let idx = ([selectedIndex].compactMap { $0 } + activeIndices).min() {
            hasSeenCuePosition = true
            return min(max(idx, 0), order.count - 1)
        }
        // Nothing selected and nothing playing. Before the show's first Go,
        // QLab still normally reports cue 1 as selected — so seeing neither
        // here, after a real position has been observed at least once
        // already, means the show played through to its last cue and QLab
        // has nothing queued next (this is exactly what happens once the
        // final cue in the list finishes, if nothing disarmed follows it to
        // stay selected). Point one past the end so the walk below sums
        // nothing, instead of defaulting to 0 and re-summing the entire,
        // already-played show as if it were still ahead of the playhead.
        return hasSeenCuePosition ? order.count : 0
    }

    // Sums the current cue's remaining time plus every armed, playable cue
    // still ahead of it in the list — not just whatever's playing right now.
    // "Remaining" is the operator's whole-rest-of-show estimate, so it needs
    // cueOrder (the full list) walked from the current position onward, not
    // just activeCueElapsed (which only knows about cues already playing).
    private func recomputeTotalRemaining() {
        guard !cueOrder.isEmpty else {
            DispatchQueue.main.async {
                self.totalRemainingSeconds = nil
                self.remainingReachedZeroAt = nil
            }
            return
        }
        let startIndex = currentStartIndex(in: cueOrder, indexForID: cueIndexForID)

        // Cues that start together — via either of QLab's two ways to build
        // a "several tracks, one Go press" cue (see startsTogether) — finish
        // around the same time as their longest member, so each such
        // cluster counts once, using the max remaining time in it, instead
        // of summing every track and inflating the total. buildCueOrder's
        // depth-first walk keeps Group siblings consecutive, and
        // auto-continue chains are inherently consecutive too, so each
        // cluster only needs to look forward from its first member.
        var total = 0.0
        var i = startIndex
        while i < cueOrder.count {
            var clusterMax = remainingSeconds(for: cueOrder[i])
            var j = i + 1
            while j < cueOrder.count, startsTogether(cueOrder[j], asPrevious: cueOrder[j - 1]) {
                clusterMax = max(clusterMax, remainingSeconds(for: cueOrder[j]))
                j += 1
            }
            total += clusterMax
            i = j
        }
        DispatchQueue.main.async {
            self.totalRemainingSeconds = total
            if total <= 0.5 {
                if self.remainingReachedZeroAt == nil { self.remainingReachedZeroAt = Date() }
            } else {
                self.remainingReachedZeroAt = nil
            }
        }
    }

    // True if `id` starts at essentially the same moment as `previous`, the
    // immediately preceding leaf in cueOrder — either they share a Timeline
    // ancestor (see timelineClusterRoot(for:)), or `previous` has
    // continueMode Auto-continue (1), a flat chain with no Group involved:
    // firing `previous` immediately fires `id` too.
    private func startsTogether(_ id: String, asPrevious previous: String) -> Bool {
        if let root = timelineClusterRoot(for: id), root == timelineClusterRoot(for: previous) {
            return true
        }
        return cueContinueMode[previous] == Self.autoContinueMode
    }

    // The outermost Timeline-mode ancestor in `leaf`'s chain, or nil if none
    // of its ancestors are in Timeline mode. Two leaves under the *same*
    // Timeline group start simultaneously even if their immediate parents
    // differ — a Timeline group's direct children are often wrapper Groups
    // rather than the tracks themselves (e.g. one sub-Group per track, for
    // per-track fades), so this has to walk the whole chain rather than
    // stop at the immediate parent. Using the outermost match (not the
    // first/nearest) also correctly merges a Timeline group nested inside
    // another Timeline group into one cluster.
    private func timelineClusterRoot(for leaf: String) -> String? {
        var root: String? = nil
        for ancestor in ancestorChain[leaf] ?? [] where cueMode[ancestor] == Self.timelineGroupMode {
            root = ancestor
        }
        return root
    }

    // A single leaf cue's own remaining playback time, or 0 if it's not a
    // playable armed cue with a known duration yet.
    private func remainingSeconds(for id: String) -> Double {
        guard let type = cueType[id], Self.playableCueTypes.contains(type) else { return 0 }
        // Default true if we haven't heard back yet, to avoid systematically
        // undercounting while armed-state replies are still in flight —
        // better to briefly overestimate than hide real remaining time
        // because of network lag.
        guard cueArmed[id] ?? true else { return 0 }
        guard let duration = cueDuration[id] else { return 0 }
        let elapsed = activeCueElapsed[id] ?? 0
        return max(0, duration - elapsed)
    }

    // For runningOrPausedCues specifically: "cues".isEmpty isn't a reliable
    // leaf signal there, because a running Group cue can appear with an
    // empty "cues" array of its own (its active children aren't nested under
    // it in that particular reply), and querying elapsed/duration on a Group
    // just returns 0. "type" is the reliable signal for that endpoint —
    // recurse through Groups, treat everything else as a leaf to query.
    private static func flattenRunningLeafCueIDs(_ cues: [[String: Any]]) -> Set<String> {
        var result = Set<String>()
        for cue in cues {
            let children = cue["cues"] as? [[String: Any]] ?? []
            if (cue["type"] as? String) == "Group" {
                result.formUnion(flattenRunningLeafCueIDs(children))
            } else if let id = cue["uniqueID"] as? String {
                result.insert(id)
            }
        }
        return result
    }

    // For cueLists/uniqueIDs specifically (unlike runningOrPausedCues above):
    // this endpoint reliably reports the true full structure, so "cues" is
    // empty if and only if a cue is an actual leaf — no need for the "type"
    // workaround needed above. Builds both the flattened show-order leaf list
    // and a lookup from any cue ID (leaf or Group) to its position in that
    // order — a Group's position is its first descendant leaf's, since
    // selecting a Group in QLab means everything in it is about to play.
    private static func buildCueOrder(_ cues: [[String: Any]]) -> (order: [String], indexForID: [String: Int], ancestorChain: [String: [String]]) {
        var order: [String] = []
        var indexForID: [String: Int] = [:]
        var ancestorChain: [String: [String]] = [:]

        // `ancestors` is nearest-first: the immediate parent's id is
        // prepended at each level down, so by the time a leaf is reached
        // it's [immediate parent, grandparent, ..., containing cue list].
        func visit(_ list: [[String: Any]], ancestors: [String]) {
            for cue in list {
                guard let id = cue["uniqueID"] as? String else { continue }
                let children = cue["cues"] as? [[String: Any]] ?? []
                if children.isEmpty {
                    indexForID[id] = order.count
                    ancestorChain[id] = ancestors
                    order.append(id)
                } else {
                    let startIdx = order.count
                    visit(children, ancestors: [id] + ancestors)
                    indexForID[id] = startIdx
                }
            }
        }
        visit(cues, ancestors: [])
        return (order, indexForID, ancestorChain)
    }

    // query is e.g. "/cue_id/{id}/actionElapsed" after the "/reply" prefix
    // has already been stripped in handleIncoming.
    private static func cueID(fromQuery query: String) -> String? {
        let parts = query.split(separator: "/")
        guard parts.count >= 2, parts[0] == "cue_id" else { return nil }
        return String(parts[1])
    }

    // QLab encodes "armed" inconsistently — sometimes a JSON bool, sometimes
    // an int (0/1) — depending on cue type/version, so both need checking.
    // Missing/unrecognized defaults to true so we never hide a cue we can't
    // actually confirm is disarmed.
    private func isCueArmed(_ cue: [String: Any]) -> Bool {
        if let b = cue["armed"] as? Bool { return b }
        if let n = cue["armed"] as? Int { return n != 0 }
        return true
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
