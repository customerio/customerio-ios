#if os(iOS)
import SwiftUI

/// Resolves the shared, branding-driven look applied across every Live Activity template.
///
/// All values come from `CIOLiveActivitiesTemplates.branding` — configured locally in the
/// widget extension and never carried in the push payload. This keeps a single app's
/// notifications visually consistent (one background, one text color) rather than letting
/// each template hardcode its own palette.
///
/// > Note: These apply to the **lock-screen** presentation. The Dynamic Island always
/// > renders on the system's black pill, so island text stays light regardless.
@available(iOS 16.2, *)
enum CIOTemplateStyle {
    /// Lock-screen card background: brand `backgroundColor`, else the template's `fallback`.
    static func background(fallback: Color) -> Color {
        CIOLiveActivitiesTemplates.branding?.backgroundColor.flatMap(Color.init(hex:)) ?? fallback
    }

    /// Lock-screen text/score color: brand `textColor`, else white.
    static var text: Color {
        CIOLiveActivitiesTemplates.branding?.textColor.flatMap(Color.init(hex:)) ?? .white
    }
}
#endif
