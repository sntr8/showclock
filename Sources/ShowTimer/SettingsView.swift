import SwiftUI
import AppKit

private enum SettingsField: Hashable {
    case host, port, passcode
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    @EnvironmentObject var display: DisplayWindowController
    @Environment(\.openWindow) private var openWindow
    @State private var portText: String = ""
    @State private var didAutoConnect = false
    // The source of truth for the focus ring is this, not the AppKit
    // responder chain — poking makeFirstResponder(nil) from outside SwiftUI
    // doesn't reliably sync with SwiftUI's own render pass for the ring.
    @FocusState private var focusedField: SettingsField?

    var body: some View {
        Form {
            // MARK: Display
            Section("Clock Display") {
                ScreenArrangementView(
                    selectedDisplayID: $settings.selectedDisplayID,
                    theme: settings.selectedTheme
                )
                .frame(height: 150)

                HStack {
                    Button(display.isShowing ? "Close Clock Display" : "Open Clock Display") {
                        if display.isShowing {
                            display.close()
                        } else if let screen = settings.resolvedScreen {
                            display.show(on: screen, settings: settings, qlab: qlab)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if let screen = settings.resolvedScreen {
                        Text(screen.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: QLab OSC
            Section("QLab OSC") {
                HStack {
                    Text("IP address")
                        .frame(width: 90, alignment: .leading)
                    TextField("", text: $settings.qlabHost)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .host)
                }
                HStack {
                    Text("Port")
                        .frame(width: 90, alignment: .leading)
                    TextField("", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .port)
                        .onAppear { portText = String(settings.qlabPort) }
                        .onChange(of: portText) { _, v in
                            if let n = Int(v), n > 0 { settings.qlabPort = n }
                        }
                }
                HStack {
                    Text("Passcode")
                        .frame(width: 90, alignment: .leading)
                    SecureField("", text: $settings.qlabPasscode)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .passcode)
                }
                Text("Only needed if the workspace has an OSC passcode set (Workspace Settings → OSC).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Connect") {
                        qlab.start(host: settings.qlabHost, port: settings.qlabPort, passcode: settings.qlabPasscode)
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
                Picker("Active theme", selection: $settings.selectedThemeID) {
                    ForEach(settings.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Button("Edit Themes...") { openWindow(id: "theme-editor") }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 700, idealHeight: 760)
        .onAppear {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            qlab.start(host: settings.qlabHost, port: settings.qlabPort, passcode: settings.qlabPasscode)
            installClickToResignMonitor()
        }
        .onDisappear {
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
        }
    }

    // A background view behind the Form doesn't work: macOS Form/List is
    // backed by an NSScrollView/NSTableView that swallows clicks in "empty"
    // row space itself, so nothing behind it ever sees the click. A local
    // monitor intercepts the click before AppKit's normal dispatch instead.
    // Clearing focusedField (not makeFirstResponder) is what actually clears
    // the ring reliably in one click — the ring is driven by SwiftUI's own
    // FocusState, not directly by the AppKit responder chain, so resigning
    // first responder from outside SwiftUI wasn't reliably syncing with its
    // render pass.
    @State private var clickMonitor: Any?
    private func installClickToResignMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            focusedField = nil
            return event
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
