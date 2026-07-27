import SwiftUI

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
        }

        WindowGroup(id: "theme-editor") {
            ThemeEditorView()
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 380)
    }
}
