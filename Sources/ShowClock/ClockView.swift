import SwiftUI

struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date
    let isPreShow: Bool

    private var timeString: String { settings.clockString(now) }

    private var showtimeString: String {
        settings.clockString(settings.showtimeDate, includeSeconds: false)
    }

    var body: some View {
        GeometryReader { geo in
            // Same sizing as CountdownView — see the comment there for why the
            // size comes from width and why fixedSize() has to accompany the
            // negative padding. One glyph shorter here (no leading sign), so
            // the clock lands slightly larger than the countdown does.
            // Sized from a fixed-width template, not the live string. In
            // 24-hour mode they're the same thing, but 12-hour swings between
            // "9:45:02 PM" and "10:45:02 PM" — sizing off the current value
            // would visibly resize the whole clock at 10:00 and again at 1:00.
            // The template is the widest form, so shorter ones simply sit with
            // a little more margin.
            let sizingTemplate = settings.use12HourClock ? "00:00:00 PM" : "00:00:00"
            let widthLimited = (geo.size.width * CountdownView.usableWidth)
                / CountdownView.advanceRatio(for: sizingTemplate)
            let heightLimited = (geo.size.height * CountdownView.maxCapFraction)
                / CountdownView.capHeightRatio
            let mainFontSize = min(widthLimited, heightLimited)
            let lineBoxSlack = mainFontSize
                * (CountdownView.lineHeightRatio - CountdownView.capHeightRatio) / 2

            let subFontSize = geo.size.height * 0.13

            // Pinned, not centred — see CountdownView for why: centring parks
            // all the leftover space at the top and bottom borders.
            VStack(spacing: 0) {
                Spacer(minLength: geo.size.height * 0.01)

                Text(timeString)
                    .font(Font.system(size: mainFontSize, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, -lineBoxSlack)
                    .foregroundStyle(settings.selectedTheme.primaryColor)

                Spacer(minLength: geo.size.height * 0.01)

                // Complementary to each other: "Show at" only makes sense
                // while genuinely waiting for the show to start; cue info
                // only makes sense once it's underway — which, without an
                // end time configured, ClockView is the only view that ever
                // renders, so this is its only home in that mode.
                if isPreShow {
                    Text("Show at \(showtimeString)")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(settings.selectedTheme.accentColor)
                } else if let nextCue = qlab.nextCueName {
                    // No else: nothing to show once there's no next cue,
                    // whether that's because QLab isn't connected or the show
                    // has simply reached its last one — "No cue selected"
                    // read like an operator mistake in both cases.
                    VStack(spacing: geo.size.height * 0.008) {
                        Text("Next:")
                        Text(nextCue)
                    }
                    .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(settings.selectedTheme.accentColor)
                }
            }
            .padding(.vertical, geo.size.height * 0.02)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
