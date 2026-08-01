import SwiftUI

// Content of the pinned mini window (see MiniWindowController): the same
// countdown/clock text as the full kiosk display, plus QLab's own "how much
// show is left" estimate (already shown to the operator in Settings via
// ShowRemainingView) — the whole point of this window is to have both
// visible at a glance while working in another app.
struct MiniClockView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let onClose: () -> Void
    @State private var now = Date()
    @State private var flashOn = true
    @State private var hoveringClose = false

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let flashTimer = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common).autoconnect()

    private var showPlainClock: Bool { settings.isShowingPlainClock(at: now, qlab: qlab) }
    private var diff: TimeInterval { settings.showEndDate.timeIntervalSince(now) }
    private var isOvertime: Bool { diff < 0 }

    private var mainText: String {
        showPlainClock ? Self.formatClock(now) : CountdownView.formatCountdown(diff)
    }

    private static func formatClock(_ date: Date) -> String {
        let c = Calendar.current
        return String(format: "%02d:%02d:%02d",
                      c.component(.hour, from: date),
                      c.component(.minute, from: date),
                      c.component(.second, from: date))
    }

    // Matches ShowRemainingView's formatting in MainView, so the number
    // reads the same here as it does in Settings.
    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private var remainingText: String? {
        guard let remaining = qlab.totalRemainingSeconds else { return nil }
        return "Set remaining: \(Self.formatDuration(remaining))"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                settings.selectedTheme.backgroundColor
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(spacing: geo.size.height * 0.06) {
                    Text(mainText)
                        .font(Font.system(size: geo.size.height * 0.42, weight: .bold).monospacedDigit())
                        .fontWidth(.compressed)
                        .minimumScaleFactor(0.01)
                        .lineLimit(1)
                        .foregroundStyle(settings.selectedTheme.primaryColor)
                        .opacity(!showPlainClock && isOvertime && !flashOn ? 0 : 1)

                    if let remainingText {
                        Text(remainingText)
                            .font(.system(size: geo.size.height * 0.13, weight: .regular, design: .monospaced))
                            .foregroundStyle(settings.selectedTheme.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .padding(geo.size.width * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Mouse-only, matching ContentView's kiosk close button — this
                // panel is a non-activating window with no title bar, so
                // there's otherwise no way to dismiss it beyond the Settings
                // toggle that opened it.
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.selectedTheme.accentColor)
                .padding(6)
                .opacity(hoveringClose ? 0.9 : 0.25)
                .onHover { hoveringClose = $0 }
            }
        }
        .frame(minWidth: 160, minHeight: 80)
        .onReceive(clock) { now = $0 }
        .onReceive(flashTimer) { _ in flashOn.toggle() }
    }
}
