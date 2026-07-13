import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// Where the floating inbox bell anchors within the overlay, driven by branding
/// (`patterns.inbox.position`). Only the bell + its unread badge move; the slide-up panel always
/// presents from the bottom edge regardless of bell position.
@available(iOS 13.0, *)
enum InboxBellPosition {
    case bottomTrailing
    case bottomLeading
    case topTrailing
    case topLeading

    /// Maps the branding position string to a bell anchor. nil / unrecognized values fall back to
    /// `.bottomTrailing` (the historical default), so a workspace that omits `position` is unchanged.
    static func resolve(_ raw: String?) -> InboxBellPosition {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bottom-left", "bottomleft", "bottom_left":
            return .bottomLeading
        case "top-right", "topright", "top_right":
            return .topTrailing
        case "top-left", "topleft", "top_left":
            return .topLeading
        default: // "bottom-right" and anything unrecognized
            return .bottomTrailing
        }
    }

    /// The SwiftUI alignment used to pin the bell inside the full-screen overlay container.
    var alignment: Alignment {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    /// Whether the bell anchors to a top corner (vs a bottom corner). Drives which screen edge the
    /// panel slides in from and which side keeps clearance for the bell.
    var isTop: Bool {
        switch self {
        case .topTrailing, .topLeading: return true
        case .bottomTrailing, .bottomLeading: return false
        }
    }
}
#endif
