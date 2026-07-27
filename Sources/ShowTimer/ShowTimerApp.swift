import SwiftUI
import AppKit

@main
struct ShowTimerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var qlab = QLabManager()
    @StateObject private var display = DisplayWindowController()

    var body: some Scene {
        // The first WindowGroup is the one macOS auto-opens at launch, so this
        // (not the theme editor below) is what appears on launch.
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(qlab)
                .environmentObject(display)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 760)
        .commands {
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
