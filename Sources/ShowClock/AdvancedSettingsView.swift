import SwiftUI
import AppKit

// Home for knobs that aren't part of day-to-day show setup — currently just
// the QLab reply port, which almost nobody ever needs to touch. Reached via
// Cmd+, / the app menu's "Settings..." item (a SwiftUI Settings scene wires
// that up automatically), not the main window.
struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let appDelegate: AppDelegate
    @State private var portText: String = ""
    @State private var keyObserver: NSObjectProtocol?

    var body: some View {
        Form {
            Section("QLab") {
                HStack {
                    Text("Reply port")
                        .frame(width: 100, alignment: .leading)
                    TextField("", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onAppear { portText = String(settings.qlabReplyPort) }
                        .onChange(of: portText) { _, v in
                            guard let n = Int(v), n > 0, n < 65536, n != settings.qlabReplyPort else { return }
                            settings.qlabReplyPort = n
                            // Live-restart if already connected, using the new
                            // port right away instead of waiting for the next
                            // manual Connect — start() tears down and rebinds
                            // the socket regardless of whether it was already
                            // open.
                            if qlab.isConnected {
                                qlab.start(
                                    host: settings.qlabHost,
                                    port: settings.qlabPort,
                                    passcode: settings.qlabPasscode,
                                    replyPort: UInt16(n)
                                )
                            }
                        }
                }
                Text("The local port QLab's OSC replies arrive on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clock Format") {
                Picker("Time format", selection: $settings.use12HourClock) {
                    Text("24-hour").tag(false)
                    Text("12-hour").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Overnight Shows") {
                HStack {
                    Text("Day cutoff")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.overnightCutoffHour) {
                        ForEach(0..<24) { h in
                            Text(settings.hourLabel(h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .labelsHidden()
                }
                Text("How late an overnight show still counts as active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Overtime") {
                HStack {
                    Text("Show end delay")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.overtimeHoldSeconds) {
                        ForEach(Self.overtimeHoldOptions, id: \.self) { seconds in
                            Text(Self.overtimeHoldLabel(seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .labelsHidden()
                }
                Text("How long to keep showing the overtime countdown after QLab reports the show has ended, before switching to the plain clock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for Updates Automatically", isOn: $settings.autoCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
        .background(WindowAccessor { window in
            // The clock display can sit on its own screen (e.g. a second
            // monitor) at a window level above ordinary windows, so a plain
            // Settings window opened while it's showing would appear behind
            // it there. Instead of fighting that z-order, just put Settings
            // on whichever screen the main window is actually on.
            reposition(window)
            guard keyObserver == nil else { return }
            // WindowAccessor's own resolve fires once, right after the
            // window is first created — that alone covers the very first
            // Cmd+,. This observer covers every time after: the Settings
            // window is reused (just hidden/shown), so this view's body/
            // WindowAccessor never runs again, but it does become key again
            // each time Cmd+, reopens it.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { reposition(window) }
            }
        })
    }

    private static let overtimeHoldOptions = [0, 15, 30, 45, 60, 90, 120, 180, 300]

    private static func overtimeHoldLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "Off" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private func reposition(_ window: NSWindow) {
        guard let screen = appDelegate.mainWindow?.screen else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        ))
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
