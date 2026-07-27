import SwiftUI
import AppKit

// Mini diagram of the connected displays, arranged to match their real
// on-screen positions. Tap a display to select it; the selected one shows a
// live miniature of the actual clock as it will render there.
struct ScreenArrangementView: View {
    @Binding var selectedDisplayID: CGDirectDisplayID
    let theme: Theme

    // NSScreen.screens is a live snapshot at read time, but nothing forces a
    // re-render when a display connects/disconnects — so without this state
    // (refreshed on the notification below) the picker just shows whatever
    // was plugged in when the view last happened to redraw for some other
    // reason, until the app restarts.
    @State private var screens: [NSScreen] = NSScreen.screens

    private var unionFrame: CGRect {
        screens.dropFirst().reduce(screens.first?.frame ?? .zero) { $0.union($1.frame) }
    }

    var body: some View {
        GeometryReader { geo in
            let union = unionFrame
            let scale = (union.width > 0 && union.height > 0)
                ? min(geo.size.width / union.width, geo.size.height / union.height) * 0.92
                : 1
            let offsetX = (geo.size.width - union.width * scale) / 2
            let offsetY = (geo.size.height - union.height * scale) / 2

            ZStack {
                ForEach(screens, id: \.displayID) { screen in
                    let isSelected = screen.displayID == selectedDisplayID
                    let width = max(screen.frame.width * scale, 1)
                    let height = max(screen.frame.height * scale, 1)
                    let midX = (screen.frame.minX - union.minX) * scale + offsetX + width / 2
                    // Flip Y: AppKit screen coordinates are bottom-left origin.
                    let midY = (union.maxY - screen.frame.maxY) * scale + offsetY + height / 2

                    // A Button, not a plain view + .onTapGesture: this sits
                    // inside a Form/List row, which has its own row-selection
                    // hit-testing that can swallow a bare tap gesture on a
                    // subview inconsistently. Buttons are the mechanism
                    // SwiftUI Lists/Forms specifically handle correctly
                    // alongside that, which a raw gesture recognizer isn't.
                    Button {
                        selectedDisplayID = screen.displayID
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.backgroundColor)

                            if isSelected {
                                MiniClockPreview(theme: theme)
                                    .padding(6)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                                    lineWidth: isSelected ? 2 : 1
                                )

                            Text(screen.localizedName)
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? theme.accentColor : .secondary)
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: midX, y: midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

// Mirrors ContentView's own clock-vs-countdown choice (via the shared
// isShowingPlainClock), so this preview shows whatever the real display is
// actually showing right now, not just always a clock.
private struct MiniClockPreview: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let theme: Theme
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayString: String {
        if settings.isShowingPlainClock(at: now, qlab: qlab) {
            let c = Calendar.current
            return String(format: "%02d:%02d:%02d",
                          c.component(.hour, from: now),
                          c.component(.minute, from: now),
                          c.component(.second, from: now))
        }
        return CountdownView.formatCountdown(settings.showEndDate.timeIntervalSince(now))
    }

    var body: some View {
        GeometryReader { geo in
            Text(displayString)
                .font(Font.system(size: geo.size.height * 0.55, weight: .bold).monospacedDigit())
                .fontWidth(.compressed)
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(theme.primaryColor)
        }
        .onReceive(timer) { now = $0 }
    }
}
