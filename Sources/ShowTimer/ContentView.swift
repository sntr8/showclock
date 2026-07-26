import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    @State private var now = Date()
    @State private var showSettings = false

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isPreShow: Bool { now < settings.showtimeDate }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            settings.selectedTheme.backgroundColor
                .ignoresSafeArea()

            if isPreShow {
                ClockView(now: now)
            } else {
                CountdownView(now: now)
            }

            // Subtle toolbar overlay (hidden in full screen via opacity-on-hover)
            HStack(spacing: 12) {
                Circle()
                    .fill(qlab.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .help(qlab.statusMessage)

                Picker("", selection: Binding(
                    get: { settings.selectedThemeID },
                    set: { settings.selectedThemeID = $0; settings.save() }
                )) {
                    ForEach(settings.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.selectedTheme.accentColor)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .opacity(0.7)
        }
        .frame(minWidth: 400, minHeight: 250)
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(qlab)
        }
    }
}
