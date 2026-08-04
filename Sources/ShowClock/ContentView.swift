import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    // A plain closure, not @EnvironmentObject var display: DisplayWindowController:
    // that would inject the controller (which owns this window) into the very
    // view hierarchy the window hosts — window -> hostingView -> environment
    // -> controller -> window, a genuine reference cycle threaded through
    // NSHostingView. A closure only captures what it needs.
    // Height of the camera housing ("notch") on the screen this window is on,
    // 0 elsewhere. The clock content is pinned to the top and bottom edges
    // (see CountdownView), which on a notched MacBook runs the current-time
    // line straight underneath the housing where it simply isn't visible.
    // The background still extends under it — only the text is inset.
    var topInset: CGFloat = 0
    let onClose: () -> Void
    @State private var now = Date()
    @State private var flashOn = true
    @State private var hoveringClose = false

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    // 1.5 Hz: a full on/off cycle every 2/3 s. Kept alongside `clock` here (not
    // inside CountdownView) so toggling it doesn't force the timer's own
    // owning view to reconstruct itself every tick.
    let flashTimer = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common).autoconnect()

    private var isPreShow: Bool { now < settings.showtimeDate }
    private var showPlainClock: Bool { settings.isShowingPlainClock(at: now, qlab: qlab) }

    var body: some View {
        GeometryReader { geo in
            // Proportional to screen size (like the rest of the app's text),
            // not a fixed pixel size — a fixed size would be tiny on a small
            // tablet-class display and comparatively huge, or too small to
            // scan, depending on whatever screen this actually ends up on.
            // Clamped so it can't get silly at either extreme.
            let qrSize = min(max(min(geo.size.width, geo.size.height) * 0.07, 44), 100)

            ZStack(alignment: .topTrailing) {
                settings.selectedTheme.backgroundColor
                    .ignoresSafeArea()

                Group {
                    if showPlainClock {
                        ClockView(now: now, isPreShow: isPreShow)
                    } else {
                        CountdownView(now: now, flashOn: flashOn)
                    }
                }
                .padding(.top, topInset)

                // White backing regardless of theme: a black QR code on the
                // Night theme's black background would be unreadable otherwise.
                if settings.showQRCode {
                    VStack(spacing: qrSize * 0.08) {
                        QRCodeView(content: "https://github.com/sntr8/showclock/releases")
                            .frame(width: qrSize, height: qrSize)
                        Text("Download ShowClock")
                            .font(.system(size: qrSize * 0.14, weight: .medium))
                            .foregroundStyle(.black)
                    }
                    .padding(qrSize * 0.1)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // Always-available, mouse-only way to close the display: keyboard
                // routing to this window can't be relied on (activation policy/
                // first-responder quirks), so this is the one guaranteed escape hatch.
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.selectedTheme.accentColor)
                .padding(16)
                .opacity(hoveringClose ? 0.9 : 0.2)
                .onHover { hoveringClose = $0 }
                .help("Close clock display")
            }
        }
        .frame(minWidth: 400, minHeight: 250)
        .onReceive(clock) { now = $0 }
        .onReceive(flashTimer) { _ in flashOn.toggle() }
    }
}
