import UIKit

extension UIColor {
    static func fromHex(_ hex: String?) -> UIColor? {
        guard let hex = hex else { return nil }

        let cleanHex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        // Validate hex string length
        guard cleanHex.count == 6 || cleanHex.count == 8 else {
            return nil
        }

        let correctHex = correctColorFormatIfNeeded(cleanHex)

        var rgbValue: UInt64 = 0
        guard Scanner(string: correctHex).scanHexInt64(&rgbValue) else {
            return nil
        }

        // Extract color components
        let red = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgbValue & 0xFF) / 255.0
        let alpha = cleanHex.count == 8
            ? CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            : 1.0

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func correctColorFormatIfNeeded(_ color: String) -> String {
        guard color.count == 8 else { return color }

        let red = color[color.index(color.startIndex, offsetBy: 0) ..< color.index(color.startIndex, offsetBy: 2)]
        let green = color[color.index(color.startIndex, offsetBy: 2) ..< color.index(color.startIndex, offsetBy: 4)]
        let blue = color[color.index(color.startIndex, offsetBy: 4) ..< color.index(color.startIndex, offsetBy: 6)]
        let alpha = color[color.index(color.startIndex, offsetBy: 6) ..< color.endIndex]

        return "\(alpha)\(red)\(green)\(blue)"
    }
}
