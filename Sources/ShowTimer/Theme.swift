import SwiftUI

struct Theme: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    var backgroundHex: String
    var primaryHex: String
    var accentHex: String

    var backgroundColor: Color { Color(hex: backgroundHex) ?? .black }
    var primaryColor: Color { Color(hex: primaryHex) ?? .white }
    var accentColor: Color { Color(hex: accentHex) ?? .gray }

    static let day = Theme(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Day",
        isBuiltIn: true,
        backgroundHex: "#FFFFFF",
        primaryHex: "#000000",
        accentHex: "#555555"
    )

    static let night = Theme(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Night",
        isBuiltIn: true,
        backgroundHex: "#000000",
        primaryHex: "#CC0000",
        accentHex: "#880000"
    )
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
