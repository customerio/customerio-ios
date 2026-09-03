import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// The inbox bell glyph, shared by the bell button and the empty state so both draw identical art.
///
/// Renders the workspace's branding SVG (`patterns.inbox.floatingIcon.svg`, pre-parsed once by
/// ``VisualInboxModel`` into an ``InboxBellGlyph``) when present, otherwise the bundled default bell
/// asset. Both are tinted with `tint`. Purely decorative: callers attach any accessibility label.
@available(iOS 13.0, *)
struct InboxBellGlyphView: View {
    let glyph: InboxBellGlyph?
    let tint: Color

    var body: some View {
        if let glyph {
            // Fill each <path> INDEPENDENTLY (like the browser) with its OWN declared fill rule so
            // overlapping paths don't flip each other's winding parity (MBL-2123). Uniform tint → the
            // stack reads as one glyph.
            ZStack {
                ForEach(Array(glyph.subpaths.enumerated()), id: \.offset) { _, subpath in
                    InboxBellIcon(subpath: subpath.path, viewBox: glyph.viewBox)
                        .fill(tint, style: FillStyle(eoFill: subpath.usesEvenOddFill))
                }
            }
        } else {
            Image("cio-inbox-bell", bundle: .cioInboxResources)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(tint)
        }
    }
}

@available(iOS 13.0, *)
extension View {
    /// Applies a host-configured accessibility label, or leaves the view unlabeled when the host
    /// provided none. The SDK never falls back to English copy of its own.
    /// `.accessibility(label:)` is the iOS 13-safe form; `.accessibilityLabel` is iOS 14+.
    @ViewBuilder
    func inboxAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            accessibility(label: Text(label))
        } else {
            self
        }
    }
}
#endif
