import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// Where the floating inbox bell anchors within the overlay, driven by branding
/// (`patterns.inbox.position`). Only the bell + its unread badge move; the inbox always presents from
/// the bottom as a sheet regardless of bell position.
///
/// The raw values are the exact strings the backend/web SDK emit (gist-web `positionStyles`):
/// `bottom-right` / `bottom-left` / `top-right` / `top-left`, with `bottom-right` as the default.
@available(iOS 13.0, *)
enum InboxBellPosition: String {
    case bottomRight = "bottom-right"
    case bottomLeft = "bottom-left"
    case topRight = "top-right"
    case topLeft = "top-left"

    /// Resolves the branding `patterns.inbox.position` string to a bell anchor. nil / unrecognized
    /// values fall back to `.bottomRight` (web's default), so a workspace that omits `position` is
    /// unchanged.
    static func resolve(_ raw: String?) -> InboxBellPosition {
        raw.flatMap(InboxBellPosition.init(rawValue:)) ?? .bottomRight
    }

    /// The SwiftUI alignment used to pin the bell inside the full-screen overlay container.
    var alignment: Alignment {
        switch self {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft: return .bottomLeading
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        }
    }
}
#endif
