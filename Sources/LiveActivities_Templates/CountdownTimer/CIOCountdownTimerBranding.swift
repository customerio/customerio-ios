#if os(iOS)
import SwiftUI

/// Local, static visual styling for the ``CIOCountdownTimerLiveActivity`` template.
///
/// Branding is your app's fixed identity — the same for every activity and every push — so you
/// supply it **once, at the widget call site**, not in the push payload:
///
/// ```swift
/// var body: some Widget {
///     CIOCountdownTimerLiveActivity(
///         branding: CIOCountdownTimerBranding(
///             logo: Image("brand-logo"),
///             background: Color.black.opacity(0.9),
///             textColor: .white
///         )
///     )
/// }
/// ```
///
/// **Background** takes either a solid `Color` (rendered with the system's native, StandBy-adaptive
/// Live Activity background) or any richer `ShapeStyle` such as a gradient (drawn directly, not
/// system-dimmed). ``textColor`` accepts any `ShapeStyle` — a color or a gradient. The `logo` is an
/// image you bundle in your widget extension (bundle image, SF Symbol, or a programmatically
/// rendered `UIImage`); the SDK never delivers assets. Every value is defaulted to a dark
/// lock-screen style.
///
/// These apply to the **lock-screen** card; the Dynamic Island renders on the system's black pill.
@available(iOS 16.2, *)
public struct CIOCountdownTimerBranding {
    /// Brand mark shown top-left of the lock-screen card and on the Dynamic Island leading edge.
    /// `nil` renders no logo.
    public var logo: Image?
    /// Resolved lock-screen background rendering path (see ``TemplateBackground``).
    let background: TemplateBackground
    /// Style for the header, title, status, and countdown text — any `ShapeStyle` (color or gradient).
    public var textColor: AnyShapeStyle

    /// Creates branding with a **solid color** background, rendered with the system's native,
    /// StandBy-adaptive Live Activity background.
    public init(
        logo: Image? = nil,
        background: Color = Color.black.opacity(0.85),
        textColor: some ShapeStyle = Color.white
    ) {
        self.logo = logo
        self.background = TemplateBackground(color: background)
        self.textColor = AnyShapeStyle(textColor)
    }

    /// Creates branding with a **gradient / other `ShapeStyle`** background, drawn directly (renders
    /// exactly as given; not system-dimmed in StandBy / Always-On Display).
    public init(
        logo: Image? = nil,
        background: some ShapeStyle,
        textColor: some ShapeStyle = Color.white
    ) {
        self.logo = logo
        self.background = TemplateBackground(style: background)
        self.textColor = AnyShapeStyle(textColor)
    }
}
#endif
