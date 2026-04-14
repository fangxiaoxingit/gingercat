import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTheme {
    static let primary = adaptiveColor(
        lightHex: "#346739",
        darkHex: "#53B762"
    )
    static let primaryDark = adaptiveColor(
        lightHex: "#28522D",
        darkHex: "#479A53"
    )
    static let primarySoft = Color(hex: "#D7E6D8")

    static let indigoBackground = Color(red: 0.14, green: 0.17, blue: 0.42)
    static let purpleBackground = Color(red: 0.21, green: 0.13, blue: 0.39)
    static let oceanBackground = Color(red: 0.10, green: 0.33, blue: 0.49)

    static let cyanGlow = Color(red: 0.42, green: 0.85, blue: 1.0)

    private static func adaptiveColor(lightHex: String, darkHex: String) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { trait in
                UIColor(hex: trait.userInterfaceStyle == .dark ? darkHex : lightHex)
            }
        )
        #else
        return Color(hex: lightHex)
        #endif
    }
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

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
        let raw = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
#endif
