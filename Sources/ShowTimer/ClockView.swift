import SwiftUI

struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: now)
    }

    private var showtimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: settings.showtimeDate)
    }

    var body: some View {
        GeometryReader { geo in
            let mainFontSize = min(geo.size.width / 5.2, geo.size.height * 0.42)
            let subFontSize = mainFontSize * 0.13

            VStack(spacing: mainFontSize * 0.08) {
                Spacer()

                Text(timeString)
                    .font(.system(size: mainFontSize, weight: .thin, design: .monospaced))
                    .foregroundStyle(settings.selectedTheme.primaryColor)
                    .lineLimit(1)

                HStack(spacing: subFontSize * 1.5) {
                    Text("Show at \(showtimeString)")
                        .foregroundStyle(settings.selectedTheme.accentColor)

                    if let next = qlab.nextCueName {
                        Text("·")
                            .foregroundStyle(settings.selectedTheme.accentColor)
                        Text("Next: \(next)")
                            .foregroundStyle(settings.selectedTheme.accentColor)
                    }
                }
                .font(.system(size: subFontSize, weight: .regular, design: .monospaced))

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
