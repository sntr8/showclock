import SwiftUI

struct CountdownView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date
    let flashOn: Bool

    private var diff: TimeInterval { settings.showEndDate.timeIntervalSince(now) }
    private var isOvertime: Bool { diff < 0 }
    private var countdownString: String { Self.formatCountdown(diff) }

    // Shared with the Settings display picker's live preview, so both always
    // render the same "-HH:MM:SS" / "+HH:MM:SS" text for a given diff.
    static func formatCountdown(_ diff: TimeInterval) -> String {
        let total = Int(abs(diff))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let digits = String(format: "%02d:%02d:%02d", h, m, s)
        return diff < 0 ? "+\(digits)" : "-\(digits)"
    }

    private var currentTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d:%02d",
                      c.component(.hour, from: now),
                      c.component(.minute, from: now),
                      c.component(.second, from: now))
    }

    var body: some View {
        GeometryReader { geo in
            // Trimmed from the main number's previous 0.82 to make real room
            // for meaningfully bigger sub-text without the two overflowing
            // the screen's fixed height between them.
            let subFontSize = geo.size.height * 0.12

            VStack(spacing: geo.size.height * 0.015) {
                Spacer()

                Text(currentTimeString)
                    .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(settings.selectedTheme.accentColor)
                    .lineLimit(1)

                Text(countdownString)
                    .font(Font.system(size: geo.size.height * 0.70, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(settings.selectedTheme.primaryColor)
                    .opacity(isOvertime && !flashOn ? 0 : 1)

                // No else: nothing to show once there's no next cue, whether
                // that's because QLab isn't connected or the show has simply
                // reached its last one — "No cue selected" read like an
                // operator mistake in both cases.
                if let next = qlab.nextCueName {
                    Text("Next: \(next)")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.selectedTheme.accentColor)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
