import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    @Environment(\.dismiss) private var dismiss
    @State private var showThemeEditor = false
    @State private var portText: String = ""
    @State private var reconnectPending = false

    var body: some View {
        Form {
            // MARK: QLab OSC
            Section("QLab OSC") {
                HStack {
                    Text("Host")
                    TextField("IP address", text: $settings.qlabHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 140)
                }
                HStack {
                    Text("Port")
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onAppear { portText = String(settings.qlabPort) }
                        .onChange(of: portText) { _, v in
                            if let n = Int(v), n > 0 { settings.qlabPort = n }
                        }
                }
                HStack {
                    Button("Connect") {
                        settings.save()
                        qlab.start(host: settings.qlabHost, port: settings.qlabPort)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(qlab.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(qlab.statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Show Times
            Section("Show Times") {
                HStack {
                    Text("Show starts")
                    Spacer()
                    HourMinutePicker(hour: $settings.showtimeHour, minute: $settings.showtimeMinute)
                }
                HStack {
                    Text("Show ends")
                    Spacer()
                    HourMinutePicker(hour: $settings.showEndHour, minute: $settings.showEndMinute)
                }
                if settings.showEndDate.timeIntervalSince(settings.showtimeDate) < 0 ||
                    (settings.showEndHour < settings.showtimeHour ||
                     (settings.showEndHour == settings.showtimeHour && settings.showEndMinute <= settings.showtimeMinute)) {
                    Text("Show end treated as next day (post-midnight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Themes
            Section("Theme") {
                Picker("Active theme", selection: Binding(
                    get: { settings.selectedThemeID },
                    set: { settings.selectedThemeID = $0; settings.save() }
                )) {
                    ForEach(settings.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Button("Edit Themes...") { showThemeEditor = true }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save & Close") {
                    settings.save()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showThemeEditor) {
            VStack(alignment: .leading) {
                Text("Themes").font(.headline).padding([.top, .horizontal])
                ThemeEditorView()
                    .environmentObject(settings)
            }
        }
    }
}

// MARK: - Hour/Minute Picker

private struct HourMinutePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: $hour) {
                ForEach(0..<24) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 60)
            .labelsHidden()

            Text(":")

            Picker("", selection: $minute) {
                ForEach(0..<60) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 60)
            .labelsHidden()
        }
    }
}
