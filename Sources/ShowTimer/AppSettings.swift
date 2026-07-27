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
    @Published var showEndHour: Int = 23 { didSet { saveIfLoaded() } }
    @Published var showEndMinute: Int = 0 { didSet { saveIfLoaded() } }
    @Published var themes: [Theme] = [.day, .night] { didSet { saveIfLoaded() } }
    @Published var selectedThemeID: UUID = Theme.night.id { didSet { saveIfLoaded() } }
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() { didSet { saveIfLoaded() } }

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
        d.set(showEndHour, forKey: "showEndHour")
        d.set(showEndMinute, forKey: "showEndMinute")
        d.set(selectedThemeID.uuidString, forKey: "selectedThemeID")
        d.set(Int(selectedDisplayID), forKey: "selectedDisplayID")
        if let encoded = try? JSONEncoder().encode(themes) { d.set(encoded, forKey: "themes") }
    }

    private func load() {
        let d = UserDefaults.standard
        if let h = d.string(forKey: "qlabHost") { qlabHost = h }
        let p = d.integer(forKey: "qlabPort"); if p > 0 { qlabPort = p }
        if let pc = d.string(forKey: "qlabPasscode") { qlabPasscode = pc }
        let sh = d.integer(forKey: "showtimeHour"); if sh > 0 { showtimeHour = sh }
        showtimeMinute = d.integer(forKey: "showtimeMinute")
        let eh = d.integer(forKey: "showEndHour"); if eh > 0 { showEndHour = eh }
        showEndMinute = d.integer(forKey: "showEndMinute")
        if let s = d.string(forKey: "selectedThemeID"), let id = UUID(uuidString: s) { selectedThemeID = id }
        if d.object(forKey: "selectedDisplayID") != nil {
            selectedDisplayID = CGDirectDisplayID(d.integer(forKey: "selectedDisplayID"))
        }
        if let data = d.data(forKey: "themes"),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            var merged: [Theme] = [.day, .night]
            for t in decoded where !t.isBuiltIn { merged.append(t) }
            themes = merged
        }
    }
}
