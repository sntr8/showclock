import SwiftUI
import AppKit

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

    private var currentTimeString: String { settings.clockString(now) }

    // Real metrics for the face below (system bold, compressed, monospaced
    // digits), read off NSFont rather than estimated from a screenshot — a
    // screenshot only ever shows the size SwiftUI had already shrunk the text
    // to, so measuring one to derive these is circular.
    // Shared with ClockView, which sizes its clock the same way.
    // How wide the string actually is at 1pt, measured rather than assumed.
    //
    // A single "advance per glyph" constant can't serve both views: it was
    // measured on "-00:58:20", whose leading hyphen is far narrower than a
    // digit, so applying that average to the plain clock's "16:29:48" (same
    // glyph count minus the hyphen, all wider characters) under-estimated the
    // width and produced a font size that overflowed the screen on both
    // edges. Measuring the real string is also what keeps this honest if the
    // format ever changes — dropping the hours segment, say.
    //
    // Cached by shape, not by value: with monospaced digits every numeral has
    // the same advance, so "16:29:48" and "17:04:51" share one entry and this
    // stays a handful of entries for the life of the app rather than a
    // measurement per tick.
    private static var advanceCache: [String: CGFloat] = [:]

    static func advanceRatio(for string: String) -> CGFloat {
        let key = String(string.map { $0.isNumber ? "0" : $0 })
        if let cached = advanceCache[key] { return cached }
        let reference: CGFloat = 100
        var descriptor = NSFont.systemFont(ofSize: reference, weight: .bold, width: .compressed)
            .fontDescriptor
        // Matches SwiftUI's .monospacedDigit() so the measurement reflects
        // what actually gets drawn.
        descriptor = descriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        guard let font = NSFont(descriptor: descriptor, size: reference) else { return 0.3484 }
        let width = (string as NSString).size(withAttributes: [.font: font]).width
        let ratio = width / reference
        guard ratio > 0 else { return 0.3484 }
        advanceCache[key] = ratio
        return ratio
    }

    static let glyphWidthRatio: CGFloat = 0.3484   // advance per glyph (fallback only)
    static let capHeightRatio: CGFloat = 0.7046    // digit height
    static let ascenderRatio: CGFloat = 0.9668     // top of the line box
    static let lineHeightRatio: CGFloat = 1.175    // reserved line box
    // Share of the screen width the digits' *advance* may occupy. Measured
    // ink runs 0.979 of advance (the rest is side bearings), so 1.0 here puts
    // the visible digits at ~98% of the screen — a ~20 px border on a 1920
    // display. Going past this (1.01 was tried) walks the ink into the bezel.
    static let usableWidth: CGFloat = 1.0
    // Ceiling on the number's share of height, so it can't crowd out the
    // sub-text on a display that's tall relative to its width.
    static let maxCapFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            // "-00:00:00" is nine glyphs, so on a stage-shaped display it's the
            // WIDTH that decides how big the number can get. Size it from
            // width and it needs no shrinking to fit — which matters, because
            // the line box a Text reserves (1.175 em) is far taller than the
            // digits drawn in it (0.705 em), and that difference is dead space
            // *inside this view's own frame* that no VStack spacing or padding
            // on the neighbours can reach. Constraining the frame's height to
            // close it only made minimumScaleFactor shrink the digits to fit
            // the smaller frame, which reopened the very gap it was meant to
            // remove. fixedSize() below locks the size so that can't happen,
            // and the negative padding then trims the reserved space for real.
            let widthLimited = (geo.size.width * Self.usableWidth)
                / Self.advanceRatio(for: countdownString)
            let heightLimited = (geo.size.height * Self.maxCapFraction) / Self.capHeightRatio
            let mainFontSize = min(widthLimited, heightLimited)
            // Half the ascent/descent the line box reserves around the digits.
            let lineBoxSlack = mainFontSize * (Self.lineHeightRatio - Self.capHeightRatio) / 2

            let subFontSize = geo.size.height * 0.13
            // The line box reserves room above the digits for ascenders this
            // string hasn't got (it's all numerals), which would otherwise
            // read as extra border margin now that this text is pinned to the
            // top edge rather than floating in a centred block.
            let clockTopSlack = subFontSize * (Self.ascenderRatio - Self.capHeightRatio)

            // Pinned rather than centred: with everything centred, the space
            // left over after laying out lands entirely at the top and bottom
            // borders, and no font tweak can move it — that leftover *is* the
            // margin. Anchoring the clock to the top edge and the cue to the
            // bottom pushes the slack into the middle instead, where it reads
            // as breathing room around the number.
            VStack(spacing: 0) {
                Text(currentTimeString)
                    .font(.system(size: subFontSize, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize()
                    .padding(.top, -clockTopSlack)
                    .foregroundStyle(settings.selectedTheme.accentColor)

                Spacer(minLength: geo.size.height * 0.01)

                Text(countdownString)
                    .font(Font.system(size: mainFontSize, weight: .bold).monospacedDigit())
                    .fontWidth(.compressed)
                    .lineLimit(1)
                    // Sized from the space available, so it already fits —
                    // fixedSize keeps SwiftUI from second-guessing that and
                    // scaling it down, which is what the negative padding
                    // below would otherwise provoke.
                    .fixedSize()
                    .padding(.vertical, -lineBoxSlack)
                    .foregroundStyle(settings.selectedTheme.primaryColor)
                    .opacity(isOvertime && !flashOn ? 0 : 1)

                Spacer(minLength: geo.size.height * 0.01)

                // No else: nothing to show once there's no next cue, whether
                // that's because QLab isn't connected or the show has simply
                // reached its last one — "No cue selected" read like an
                // operator mistake in both cases.
                if let next = qlab.nextCueName {
                    VStack(spacing: geo.size.height * 0.008) {
                        Text("Next:")
                        Text(next)
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
