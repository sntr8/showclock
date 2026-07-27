import Foundation
import SwiftUI
import AppKit
import Combine

class AppSettings: ObservableObject {
    @Published var qlabHost: String = "127.0.0.1" { didSet { saveIfLoaded() } }
    @Published var qlabPort: Int = 53000 { didSet { saveIfLoaded() } }
    @Published var qlabPasscode: String = "" { didSet { saveIfLoaded() } }
    @Published var showtimeHour: Int = 20 { didSet { saveIfLoaded() } }
    @Published var showtimeMinute: Int = 0 { didSet { saveIfLoaded() } }
    @Published var showEndEnabled: Bool = true { didSet { saveIfLoaded() } }
    @Published var showEndHour: Int = 23 { didSet { saveIfLoaded() } }
    @Published var showEndMinute: Int = 0 { didSet { saveIfLoaded() } }
    @Published var themes: [Theme] = [.day, .night] { didSet { saveIfLoaded() } }
    @Published var selectedThemeID: UUID = Theme.night.id { didSet { saveIfLoaded() } }
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() { didSet { saveIfLoaded() } }
    @Published var autoOpenClockOnLaunch: Bool = false { didSet { saveIfLoaded() } }
    @Published var showQRCode: Bool = true { didSet { saveIfLoaded() } }

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
    // overtime view) at a given moment. Pure function of settings + QLab
    // state — no session-local "sticky" flag needed: once QLab's own
    // rest-of-show estimate reaches zero, it naturally stays there (nothing
    // spontaneously adds more cues), so this is safe to recompute every tick
    // from scratch. Shared by the real display (ContentView) and the
    // Settings display picker's live preview, so both always agree.
    func isShowingPlainClock(at now: Date, qlab: QLabManager) -> Bool {
        guard showEndEnabled else { return true }
        if now < showtimeDate { return true }
        guard now >= showEndDate else { return false }
        // Past show end: keep showing overtime for as long as QLab says
        // there's still show left, however long that takes — no fixed cutoff.
        // Without a QLab connection there's no way to know, so don't assume
        // the show is over; keep showing overtime rather than guessing.
        if qlab.isConnected, let remaining = qlab.totalRemainingSeconds {
            return remaining <= 0.5
        }
        return false
    }

    // Returns today's date with the showtime HH:MM. Always "today" so the app resets naturally.
    var showtimeDate: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = showtimeHour
        comps.minute = showtimeMinute
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    // Returns show end date. If the end time is at or before showtime, adds 1 day (post-midnight shows).
    var showEndDate: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = showEndHour
        comps.minute = showEndMinute
        comps.second = 0
        let endSameDay = cal.date(from: comps) ?? Date()
        if showEndHour < showtimeHour || (showEndHour == showtimeHour && showEndMinute <= showtimeMinute) {
            return cal.date(byAdding: .day, value: 1, to: endSameDay)!
        }
        return endSameDay
    }

    init() {
        load()
        isLoading = false
    }

    func save() {
        let d = UserDefaults.standard
        d.set(qlabHost, forKey: "qlabHost")
        d.set(qlabPort, forKey: "qlabPort")
        d.set(qlabPasscode, forKey: "qlabPasscode")
        d.set(showtimeHour, forKey: "showtimeHour")
        d.set(showtimeMinute, forKey: "showtimeMinute")
        d.set(showEndEnabled, forKey: "showEndEnabled")
        d.set(showEndHour, forKey: "showEndHour")
        d.set(showEndMinute, forKey: "showEndMinute")
        d.set(selectedThemeID.uuidString, forKey: "selectedThemeID")
        d.set(Int(selectedDisplayID), forKey: "selectedDisplayID")
        d.set(autoOpenClockOnLaunch, forKey: "autoOpenClockOnLaunch")
        d.set(showQRCode, forKey: "showQRCode")
        if let encoded = try? JSONEncoder().encode(themes) { d.set(encoded, forKey: "themes") }
    }

    private func load() {
        let d = UserDefaults.standard
        if let h = d.string(forKey: "qlabHost") { qlabHost = h }
        let p = d.integer(forKey: "qlabPort"); if p > 0 { qlabPort = p }
        if let pc = d.string(forKey: "qlabPasscode") { qlabPasscode = pc }
        let sh = d.integer(forKey: "showtimeHour"); if sh > 0 { showtimeHour = sh }
        showtimeMinute = d.integer(forKey: "showtimeMinute")
        if d.object(forKey: "showEndEnabled") != nil { showEndEnabled = d.bool(forKey: "showEndEnabled") }
        let eh = d.integer(forKey: "showEndHour"); if eh > 0 { showEndHour = eh }
        showEndMinute = d.integer(forKey: "showEndMinute")
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
        if let data = d.data(forKey: "themes"),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            var merged: [Theme] = [.day, .night]
            for t in decoded where !t.isBuiltIn { merged.append(t) }
            themes = merged
        }
    }
}
