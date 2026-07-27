import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    @EnvironmentObject var display: DisplayWindowController
    @State private var now = Date()
    @State private var flashOn = true
    @State private var hoveringClose = false

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    // 1.5 Hz: a full on/off cycle every 2/3 s. Kept alongside `clock` here (not
    // inside CountdownView) so toggling it doesn't force the timer's own
    // owning view to reconstruct itself every tick.
    let flashTimer = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common).autoconnect()

    private var isPreShow: Bool { now < settings.showtimeDate }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            settings.selectedTheme.backgroundColor
                .ignoresSafeArea()

            if isPreShow {
                ClockView(now: now)
            } else {
                CountdownView(now: now, flashOn: flashOn)
            }

            // Always-available, mouse-only way to close the display: keyboard
            // routing to this window can't be relied on (activation policy/
            // first-responder quirks), so this is the one guaranteed escape hatch.
            Button {
                display.close()
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
        .frame(minWidth: 400, minHeight: 250)
        .onReceive(clock) { now = $0 }
        .onReceive(flashTimer) { _ in flashOn.toggle() }
    }
}
