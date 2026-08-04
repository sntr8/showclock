import SwiftUI
import AppKit

// Mini diagram of the connected displays, arranged to match their real
// on-screen positions. Tap a display to select it; the selected one shows a
// live miniature of the actual clock as it will render there.
struct ScreenArrangementView: View {
    @Binding var selectedDisplayID: CGDirectDisplayID
    let theme: Theme

    // A plain value snapshot of everything this diagram draws.
    //
    // Holding [NSScreen] here instead looked correct and silently never
    // updated: NSScreen is a class, and rearranging or hot-plugging displays
    // mutates the *existing* instances rather than producing new ones. So
    // re-reading NSScreen.screens handed back an array of the same object
    // identities, which compares equal to what @State already held — SwiftUI
    // saw no change and skipped the redraw, even though the frames inside had
    // moved. Copying the values out means a moved display genuinely differs.
    private struct ScreenInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let frame: CGRect
        let name: String
    }

    @State private var screens: [ScreenInfo] = ScreenArrangementView.currentScreens()

    private static func currentScreens() -> [ScreenInfo] {
        NSScreen.screens.map {
            ScreenInfo(id: $0.displayID, frame: $0.frame, name: $0.localizedName)
        }
    }

    private var unionFrame: CGRect {
        screens.dropFirst().reduce(screens.first?.frame ?? .zero) { $0.union($1.frame) }
    }

    private func refreshScreens() {
        screens = Self.currentScreens()
        // NSScreen.screens can still report the previous layout at the moment
        // the notification lands — the window server hasn't necessarily
        // settled yet. A deferred second read picks up the final arrangement,
        // otherwise a hot-plug leaves the diagram one change behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            screens = Self.currentScreens()
        }
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
                ForEach(screens) { screen in
                    let isSelected = screen.id == selectedDisplayID
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
                        selectedDisplayID = screen.id
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

                            // Both states draw from the theme rather than
                            // falling back to .secondary for the unselected
                            // one: .secondary resolves against the system
                            // appearance (dark), so it came out a pale grey
                            // and vanished against the theme's own light
                            // backgroundColor — the name was being rendered
                            // all along, just invisibly, which read as "only
                            // the selected display is labelled".
                            Text(screen.name)
                                .font(.system(size: 9))
                                .foregroundStyle(theme.accentColor.opacity(isSelected ? 1 : 0.7))
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
        // The notification alone wasn't enough: `screens` is @State, so it's
        // seeded once and then only ever changed by a handler that is
        // subscribed *while this view is on screen*. Plug or unplug a display
        // with Settings closed and nothing observes it, so reopening Settings
        // still showed the old arrangement and only relaunching fixed it.
        // Re-reading on appear covers exactly that gap.
        .onAppear { refreshScreens() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshScreens()
        }
        // Belt and braces for the common case of plugging a display in while
        // another app is focused: returning to ShowClock re-reads the layout
        // even if the notification was missed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreens()
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
