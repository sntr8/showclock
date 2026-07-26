import SwiftUI

@main
struct ShowTimerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var qlab = QLabManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(qlab)
                .onAppear {
                    qlab.start(host: settings.qlabHost, port: settings.qlabPort)
                }
        }
        .windowStyle(.automatic)
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

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(qlab)
        }
    }
}
