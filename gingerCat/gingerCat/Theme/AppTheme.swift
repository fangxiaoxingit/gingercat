import SwiftUI

enum AppTheme {
    static let primary = Color(hex: "#346739")
    static let primaryDark = Color(hex: "#28522D")
    static let primarySoft = Color(hex: "#D7E6D8")

    static let indigoBackground = Color(red: 0.14, green: 0.17, blue: 0.42)
    static let purpleBackground = Color(red: 0.21, green: 0.13, blue: 0.39)
    static let oceanBackground = Color(red: 0.10, green: 0.33, blue: 0.49)

    static let cyanGlow = Color(red: 0.42, green: 0.85, blue: 1.0)
}

extension Color {
    init(hex: String) {
        let raw = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
