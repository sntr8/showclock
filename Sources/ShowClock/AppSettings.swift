import Foundation
import SwiftUI
import AppKit
import Combine

class AppSettings: ObservableObject {
    @Published var qlabHost: String = "127.0.0.1" { didSet { saveIfLoaded() } }
    @Published var qlabPort: Int = 53000 { didSet { saveIfLoaded() } }
    // Local UDP port QLab's OSC replies arrive on. Rarely needs changing —
    // only if something else on the machine is already using 53001 — so it
    // lives in the Cmd+, Settings scene rather than the main window.
    @Published var qlabReplyPort: Int = 53001 { didSet { saveIfLoaded() } }
    @Published var qlabPasscode: String = "" { didSet { saveIfLoaded() } }
    @Published var showtimeHour: Int = 20 { didSet { saveIfLoaded() } }
    @Published var showtimeMinute: Int = 0 { didSet { saveIfLoaded() } }
    @Published var showEndEnabled: Bool = true { didSet { saveIfLoaded() } }
    @Published var showEndHour: Int = 23 { didSet { saveIfLoaded() } }
    @Published var showEndMinute: Int = 0 { didSet { saveIfLoaded() } }
    // For overnight shows, how late into the morning "last night's" show
    // still counts as the active one (for overtime purposes) before the
    // clock switches to treating tonight's occurrence as upcoming. Rarely
    // needs changing, so it lives in the Cmd+, Settings scene.
    @Published var overnightCutoffHour: Int = 5 { didSet { saveIfLoaded() } }
    // 24-hour by default: it's the theatre/broadcast convention, and it's what
    // every build before this one showed, so an existing install doesn't
    // silently change format under the operator.
    @Published var use12HourClock: Bool = false { didSet { saveIfLoaded() } }
    // How long to keep showing the overtime countdown after QLab's own
    // rest-of-show estimate reaches zero, before cutting to the plain clock.
    // An instant cut read as jarring/alarming to operators — this gives them
    // a moment to see the show actually finished instead of the display just
    // changing out from under them. Configurable (Cmd+, → Overtime) since
    // how long that grace period should be is a show-by-show/operator
    // preference, not a fixed constant.
    @Published var overtimeHoldSeconds: Int = 60 { didSet { saveIfLoaded() } }
    @Published var themes: [Theme] = [.day, .night] { didSet { saveIfLoaded() } }
    @Published var selectedThemeID: UUID = Theme.night.id { didSet { saveIfLoaded() } }
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() { didSet { saveIfLoaded() } }
    @Published var autoOpenClockOnLaunch: Bool = false { didSet { saveIfLoaded() } }
    @Published var showQRCode: Bool = true { didSet { saveIfLoaded() } }
    @Published var autoCheckForUpdates: Bool = false { didSet { saveIfLoaded() } }
    // Whether the one-time "want automatic update checks?" prompt has been
    // shown yet — separate from autoCheckForUpdates itself so declining it
    // is remembered too (otherwise every launch would ask again).
    @Published var hasAskedAboutAutoUpdateCheck: Bool = false { didSet { saveIfLoaded() } }

    // Guards against `load()` itself triggering the didSet-save chain above:
    // without this, setting the first property (before the rest have been
    // read from UserDefaults) would immediately re-save and clobber the
    // not-yet-loaded fields back to their hardcoded defaults.
    private var isLoading = true
    private func saveIfLoaded() {
        guard !isLoading else { return }
        save()
    }

    // The screen to open the clock on. Falls back to the main screen if the
    // previously chosen display isn't connected anymore.
    var resolvedScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.displayID == selectedDisplayID }) ?? NSScreen.main
    }

    var selectedTheme: Theme {
        themes.first(where: { $0.id == selectedThemeID }) ?? .night
    }

    // Whether the display should show the plain clock (vs. the countdown/
    // overtime view) at a given moment. Almost a pure function of settings +
    // QLab state — the one exception is remainingReachedZeroAt (owned by
    // QLabManager, not recomputed here), which is what makes the switch to
    // plain clock land `overtimeHoldSeconds` after QLab's estimate hits zero
    // rather than instantly. Shared by the real display (ContentView) and
    // the Settings display picker's live preview, so both always agree.
    func isShowingPlainClock(at now: Date, qlab: QLabManager) -> Bool {
        guard showEndEnabled else { return true }
        if now < showtimeDate { return true }
        guard now >= showEndDate else { return false }
        // Past show end: keep showing overtime for as long as QLab says
        // there's still show left, however long that takes — no fixed cutoff.
        // Without a QLab connection there's no way to know, so don't assume
        // the show is over; keep showing overtime rather than guessing.
        if qlab.isConnected, let remaining = qlab.totalRemainingSeconds {
            guard remaining <= 0.5 else { return false }
            guard let zeroAt = qlab.remainingReachedZeroAt else { return true }
            return now.timeIntervalSince(zeroAt) >= TimeInterval(overtimeHoldSeconds)
        }
        return false
    }

    // The show window (start, end) anchored to a given calendar day — end
    // pushed a day later than start if it's at or before it (post-midnight
    // shows).
    private func window(anchoredToDayOf date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = showtimeHour
        comps.minute = showtimeMinute
        comps.second = 0
        let start = cal.date(from: comps) ?? date
        comps.hour = showEndHour
        comps.minute = showEndMinute
        let endSameDay = cal.date(from: comps) ?? date
        let end = (showEndHour < showtimeHour || (showEndHour == showtimeHour && showEndMinute <= showtimeMinute))
            ? cal.date(byAdding: .day, value: 1, to: endSameDay) ?? endSameDay
            : endSameDay
        return (start, end)
    }

    // Anchoring purely to "today" broke as soon as a post-midnight show (e.g.
    // 23:00-01:00) crossed into the new calendar day: showtimeDate would
    // recompute to a future time later *that same new day*, making an
    // already-running (or still-in-overtime) overnight show look like it
    // hadn't started yet. Anchor to yesterday's occurrence instead for as
    // long as it's still running, or only recently ended (before
    // overnightCutoffHour) — not just until its own nominal end, otherwise
    // the moment "now" ticks past a scheduled 01:35 end, this would
    // immediately start comparing against *tonight's* not-yet-started show
    // instead of checking whether last night's is still in overtime.
    private var activeWindow: (start: Date, end: Date) {
        let now = Date()
        let today = window(anchoredToDayOf: now)
        guard now < today.start, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) else {
            return today
        }
        let priorNight = window(anchoredToDayOf: yesterday)
        let cal = Calendar.current
        var cutoffComps = cal.dateComponents([.year, .month, .day], from: now)
        cutoffComps.hour = overnightCutoffHour
        cutoffComps.minute = 0
        cutoffComps.second = 0
        let cutoff = cal.date(from: cutoffComps) ?? now
        if now < cutoff {
            return priorNight
        }
        return today
    }

    // Returns the showtime HH:MM on whichever day is actually in progress.
    // One place decides how a wall-clock time reads, so the kiosk display,
    // the mini window and Settings can't disagree. The countdown is
    // deliberately NOT routed through here — "-00:45:12" is a duration, and
    // AM/PM is meaningless on a duration.
    func clockString(_ date: Date, includeSeconds: Bool = true) -> String {
        let c = Calendar.current
        var h = c.component(.hour, from: date)
        let m = c.component(.minute, from: date)
        let s = c.component(.second, from: date)
        guard use12HourClock else {
            return includeSeconds
                ? String(format: "%02d:%02d:%02d", h, m, s)
                : String(format: "%02d:%02d", h, m)
        }
        let suffix = h < 12 ? "AM" : "PM"
        h = h % 12
        if h == 0 { h = 12 }
        return includeSeconds
            ? String(format: "%d:%02d:%02d %@", h, m, s, suffix)
            : String(format: "%d:%02d %@", h, m, suffix)
    }

    var showtimeDate: Date { activeWindow.start }

    // Returns the show end date, on the day after showtime if the show crosses midnight.
    var showEndDate: Date { activeWindow.end }

    init() {
        load()
        isLoading = false
    }

    func save() {
        let d = UserDefaults.standard
        d.set(qlabHost, forKey: "qlabHost")
        d.set(qlabPort, forKey: "qlabPort")
        d.set(qlabReplyPort, forKey: "qlabReplyPort")
        d.set(qlabPasscode, forKey: "qlabPasscode")
        d.set(showtimeHour, forKey: "showtimeHour")
        d.set(showtimeMinute, forKey: "showtimeMinute")
        d.set(showEndEnabled, forKey: "showEndEnabled")
        d.set(showEndHour, forKey: "showEndHour")
        d.set(showEndMinute, forKey: "showEndMinute")
        d.set(overnightCutoffHour, forKey: "overnightCutoffHour")
        d.set(use12HourClock, forKey: "use12HourClock")
        d.set(overtimeHoldSeconds, forKey: "overtimeHoldSeconds")
        d.set(selectedThemeID.uuidString, forKey: "selectedThemeID")
        d.set(Int(selectedDisplayID), forKey: "selectedDisplayID")
        d.set(autoOpenClockOnLaunch, forKey: "autoOpenClockOnLaunch")
        d.set(showQRCode, forKey: "showQRCode")
        d.set(autoCheckForUpdates, forKey: "autoCheckForUpdates")
        d.set(hasAskedAboutAutoUpdateCheck, forKey: "hasAskedAboutAutoUpdateCheck")
        if let encoded = try? JSONEncoder().encode(themes) { d.set(encoded, forKey: "themes") }
    }

    private func load() {
        let d = UserDefaults.standard
        if let h = d.string(forKey: "qlabHost") { qlabHost = h }
        let p = d.integer(forKey: "qlabPort"); if p > 0 { qlabPort = p }
        let rp = d.integer(forKey: "qlabReplyPort"); if rp > 0 { qlabReplyPort = rp }
        if let pc = d.string(forKey: "qlabPasscode") { qlabPasscode = pc }
        let sh = d.integer(forKey: "showtimeHour"); if sh > 0 { showtimeHour = sh }
        showtimeMinute = d.integer(forKey: "showtimeMinute")
        if d.object(forKey: "showEndEnabled") != nil { showEndEnabled = d.bool(forKey: "showEndEnabled") }
        let eh = d.integer(forKey: "showEndHour"); if eh > 0 { showEndHour = eh }
        showEndMinute = d.integer(forKey: "showEndMinute")
        let oc = d.integer(forKey: "overnightCutoffHour"); if oc > 0 { overnightCutoffHour = oc }
        if d.object(forKey: "overtimeHoldSeconds") != nil { overtimeHoldSeconds = d.integer(forKey: "overtimeHoldSeconds") }
        if let s = d.string(forKey: "selectedThemeID"), let id = UUID(uuidString: s) { selectedThemeID = id }
        if d.object(forKey: "selectedDisplayID") != nil {
            selectedDisplayID = CGDirectDisplayID(d.integer(forKey: "selectedDisplayID"))
        }
        if d.object(forKey: "autoOpenClockOnLaunch") != nil {
            autoOpenClockOnLaunch = d.bool(forKey: "autoOpenClockOnLaunch")
        }
        if d.object(forKey: "showQRCode") != nil {
            showQRCode = d.bool(forKey: "showQRCode")
        }
        if d.object(forKey: "use12HourClock") != nil {
            use12HourClock = d.bool(forKey: "use12HourClock")
        }
        if d.object(forKey: "autoCheckForUpdates") != nil {
            autoCheckForUpdates = d.bool(forKey: "autoCheckForUpdates")
        }
        if d.object(forKey: "hasAskedAboutAutoUpdateCheck") != nil {
            hasAskedAboutAutoUpdateCheck = d.bool(forKey: "hasAskedAboutAutoUpdateCheck")
        }
        if let data = d.data(forKey: "themes"),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            var merged: [Theme] = [.day, .night]
            for t in decoded where !t.isBuiltIn { merged.append(t) }
            themes = merged
        }
    }
}
