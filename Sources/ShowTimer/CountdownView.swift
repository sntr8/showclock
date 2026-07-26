import SwiftUI

struct CountdownView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date

    private var remaining: TimeInterval {
        max(0, settings.showEndDate.timeIntervalSince(now))
    }

    private var countdownString: String {
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    var body: some View {
        GeometryReader { geo in
            let mainFontSize = min(geo.size.width / 3.8, geo.size.height * 0.5)
            let subFontSize = mainFontSize * 0.14

            VStack(spacing: mainFontSize * 0.08) {
                Spacer()

                Text(countdownString)
                    .font(.system(size: mainFontSize, weight: .thin, design: .monospaced))
                    .foregroundStyle(remaining > 0
                        ? settings.selectedTheme.primaryColor
                        : settings.selectedTheme.accentColor)
                    .lineLimit(1)

                if let next = qlab.nextCueName {
                    Text("Next: \(next)")
                        .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.selectedTheme.accentColor)
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
