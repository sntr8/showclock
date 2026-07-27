import SwiftUI

struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date
    let isPreShow: Bool

    private var timeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d:%02d",
                      c.component(.hour, from: now),
                      c.component(.minute, from: now),
                      c.component(.second, from: now))
    }

    private var showtimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: settings.showtimeDate)
    }

    var body: some View {
        GeometryReader { geo in
            let subFontSize = geo.size.height * 0.09

            VStack(spacing: geo.size.height * 0.02) {
                Spacer()

                Text(timeString)
                    .font(Font.system(size: geo.size.height * 0.82, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(settings.selectedTheme.primaryColor)

                // Complementary to each other: "Show at" only makes sense
                // while genuinely waiting for the show to start; cue info
                // only makes sense once it's underway — which, without an
                // end time configured, ClockView is the only view that ever
                // renders, so this is its only home in that mode.
                if isPreShow {
                    Text("Show at \(showtimeString)")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.selectedTheme.accentColor)
                        .lineLimit(1)
                } else if let nextCue = qlab.nextCueName {
                    Text("Next: \(nextCue)")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.selectedTheme.accentColor)
                        .lineLimit(1)
                } else {
                    Text("No cue selected")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.selectedTheme.accentColor.opacity(0.4))
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
