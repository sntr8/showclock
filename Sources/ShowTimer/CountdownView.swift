import SwiftUI

struct CountdownView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date
    let flashOn: Bool

    private var diff: TimeInterval { settings.showEndDate.timeIntervalSince(now) }
    private var isOvertime: Bool { diff < 0 }

    private var countdownString: String {
        let total = Int(abs(diff))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let digits = String(format: "%02d:%02d:%02d", h, m, s)
        return isOvertime ? "+\(digits)" : digits
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
            let subFontSize = geo.size.height * 0.055

            VStack(spacing: geo.size.height * 0.02) {
                Spacer()

                Text(currentTimeString)
                    .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(settings.selectedTheme.accentColor)
                    .lineLimit(1)

                Text(countdownString)
                    .font(Font.system(size: geo.size.height * 0.82, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isOvertime
                        ? settings.selectedTheme.accentColor
                        : settings.selectedTheme.primaryColor)
                    .opacity(isOvertime && !flashOn ? 0 : 1)

                if let next = qlab.nextCueName {
                    Text("Next: \(next)")
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
