import SwiftUI
import CoreImage

// Renders a QR code for a string using Core Image's built-in generator — no
// external dependency needed. Generated once and cached in @State rather than
// regenerated on every redraw.
struct QRCodeView: View {
    let content: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard image == nil else { return }
            image = Self.generate(content)
        }
    }

    private static func generate(_ string: String) -> CGImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        // The raw output is only a handful of pixels per module (e.g. ~25x25
        // for a short URL) — scale up before rasterizing so it isn't blurry
        // once SwiftUI stretches it to display size.
        let scale: CGFloat = 10
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(transformed, from: transformed.extent)
    }
}
