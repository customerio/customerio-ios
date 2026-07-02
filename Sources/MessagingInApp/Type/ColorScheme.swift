import UIKit

public enum ColorScheme: Equatable {
    case light
    case dark
    case auto

    func resolve(with traitCollection: UITraitCollection) -> String {
        switch self {
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .auto:
            return traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        }
    }
}
