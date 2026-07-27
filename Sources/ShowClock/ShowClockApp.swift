import SwiftUI
import AppKit

@main
struct ShowClockApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var qlab = QLabManager()
    @StateObject private var display = DisplayWindowController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The first WindowGroup is the one macOS auto-opens at launch, so this
        // (not the theme editor below) is what appears on launch.
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(qlab)
                .environmentObject(display)
                .onAppear { appDelegate.display = display }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateChecker.check(interactive: true)
                }
                Toggle("Check for Updates Automatically", isOn: $settings.autoCheckForUpdates)
            }
            CommandGroup(after: .appInfo) {
                Divider()
                ForEach(Array(settings.themes.enumerated()), id: \.element.id) { index, theme in
                    Button(theme.name) {
                        settings.selectedThemeID = theme.id
                        settings.save()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Button(settings.showQRCode ? "Hide QR Code" : "Show QR Code") {
                    guard settings.showQRCode else {
                        settings.showQRCode = true
                        return
                    }

                    let alert = NSAlert()
                    alert.messageText = "Hide QR Code"
                    alert.informativeText = "Before it goes: ShowClock is free and open-source. If you'd still like to support future updates, you can drop a tip on Ko-fi!"
                    alert.addButton(withTitle: "Visit Ko-fi")
                    alert.addButton(withTitle: "Just Hide QR")
                    // NSAlert's Return-key default is the first-added button, but the
                    // initial keyboard focus (what Space bar activates) is separate and
                    // doesn't follow — `initialFirstResponder` only actually takes when
                    // the alert runs as a sheet; for a plain runModal() application-modal
                    // alert, NSAlert reassigns focus internally regardless of what's set
                    // beforehand. Presenting as a sheet (anchored to whatever window is
                    // currently key) is what makes Space also trigger "Visit Ko-fi".
                    let finish: (NSApplication.ModalResponse) -> Void = { response in
                        if response == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/sntr8")!)
                        }
                        settings.showQRCode = false
                    }
                    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                        alert.window.initialFirstResponder = alert.buttons[0]
                        alert.beginSheetModal(for: window, completionHandler: finish)
                    } else {
                        finish(alert.runModal())
                    }
                }
            }
        }

        WindowGroup(id: "theme-editor") {
            ThemeEditorView()
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 380)
    }
}

// Guards against accidentally quitting mid-show: Cmd+Q (or Dock > Quit)
// closes the clock display and drops the QLab connection instantly with no
// warning otherwise, which would be disruptive to do by accident during a
// live performance.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var display: DisplayWindowController?

    // A second launch (double-click, Spotlight, "open -a" from a script, etc.)
    // would otherwise run alongside the first, both trying to bind QLab's OSC
    // reply port (53001) — the loser saw a bare "Failed to bind port 53001" in
    // Settings with no hint why. Hand off to the already-running instance and
    // quit instead, before anything (including that bind) gets a chance to run.
    //
    // Matched by executable path, not bundleIdentifier: an unbundled dev
    // build (swift run / .build/debug/ShowClock) has no Info.plist, so
    // Bundle.main.bundleIdentifier is nil there and would never match.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let executableURL = Bundle.main.executableURL else { return }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.executableURL == executableURL
        }
        guard let existing = others.first else { return }
        existing.activate()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let display, display.isShowing else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "The clock display is currently open."
        alert.informativeText = "Quitting will close it and disconnect from QLab."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
