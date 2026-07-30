#if os(iOS)
import SwiftUI

/// Shared internal representation of a template's resolved lock-screen background path.
///
/// Chosen automatically from which `background:` initializer a branding type used — a solid `Color`
/// maps to ``tint`` (the system's native, StandBy-adaptive background), any other `ShapeStyle` maps
/// to ``styled`` (drawn directly, so gradients/materials work but there is no system dimming).
@available(iOS 16.2, *)
enum TemplateBackground {
    case tint(Color)
    case styled(AnyShapeStyle)

    /// Wraps a solid color as the system-tint path.
    init(color: Color) {
        self = .tint(color)
    }

    /// Wraps any `ShapeStyle` (gradient, material, …) as the directly-drawn path.
    init(style: some ShapeStyle) {
        self = .styled(AnyShapeStyle(style))
    }
}

/// Applies a ``TemplateBackground`` to a template's lock-screen view: the system
/// `activityBackgroundTint` for a solid color, or a directly-drawn full-bleed style otherwise.
@available(iOS 16.2, *)
struct TemplateBackgroundModifier: ViewModifier {
    let background: TemplateBackground

    func body(content: Content) -> some View {
        switch background {
        case .tint(let color):
            content.activityBackgroundTint(color)
        case .styled(let style):
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(style)
                .activitySystemActionForegroundColor(.white)
        }
    }
}

/// A host-bundled brand mark scaled to a square, or nothing when no logo was supplied. Shared by the
/// built-in templates for the lock-screen and Dynamic Island leading positions.
@available(iOS 16.2, *)
struct BrandLogo: View {
    let logo: Image?
    let size: CGFloat

    var body: some View {
        if let logo = logo {
            logo.resizable().scaledToFit().frame(width: size, height: size)
        }
    }
}
#endif
