import SwiftUI

struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var qlab: QLabManager
    let now: Date

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
            let subFontSize = geo.size.height * 0.055

            VStack(spacing: geo.size.height * 0.02) {
                Spacer()

                Text(timeString)
                    .font(Font.system(size: geo.size.height * 0.82, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(settings.selectedTheme.primaryColor)

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
                .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
