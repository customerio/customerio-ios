#if os(iOS)
import SwiftUI

/// Local, static visual styling for the ``CIOSegmentsLiveActivity`` template.
///
/// Branding is your app's fixed identity — the same for every activity and every push — so you
/// supply it **once, at the widget call site**, not in the push payload:
///
/// ```swift
/// var body: some Widget {
///     CIOSegmentsLiveActivity(
///         branding: CIOSegmentsBranding(
///             logo: Image("brand-logo"),
///             background: LinearGradient(colors: [.black, .indigo], startPoint: .top, endPoint: .bottom),
///             textColor: .white,
///             progressComplete: .white,
///             progressIncomplete: Color(white: 0.4)
///         )
///     )
/// }
/// ```
///
/// **Background** takes either a solid `Color` or any richer `ShapeStyle` (a gradient, a material),
/// and the SDK does the right thing for each:
/// - A **`Color`** is rendered with the system's native Live Activity background, so it adapts to
///   the environment — notably it is dimmed in StandBy and on the Always-On Display.
/// - A **gradient / other `ShapeStyle`** is drawn directly (the system background can't express it).
///   It renders exactly as given and is *not* system-dimmed, so prefer darker values.
///
/// ``textColor``, ``progressComplete`` and ``progressIncomplete`` likewise accept any `ShapeStyle` —
/// pass `.white` or a gradient interchangeably. The `logo` is an image you bundle in your widget
/// extension (bundle image, SF Symbol, or a programmatically rendered `UIImage`); the SDK never
/// delivers assets. Every value is defaulted to a dark lock-screen style.
///
/// These apply to the **lock-screen** card. The Dynamic Island renders on the system's black pill,
/// so its text stays light; only ``progressComplete``/``progressIncomplete`` carry into it.
@available(iOS 16.2, *)
public struct CIOSegmentsBranding {
    /// Brand mark shown top-left of the lock-screen card and on the Dynamic Island leading edge.
    /// `nil` renders no logo.
    public var logo: Image?
    /// Resolved lock-screen background rendering path (see ``TemplateBackground``).
    let background: TemplateBackground
    /// Style for the header, status, and substatus text — any `ShapeStyle` (color or gradient).
    public var textColor: AnyShapeStyle
    /// Style of the filled (completed) progress segments — any `ShapeStyle` (color or gradient).
    public var progressCompleteStyle: AnyShapeStyle
    /// Style of the unfilled (remaining) progress segments — any `ShapeStyle` (color or gradient).
    public var progressIncompleteStyle: AnyShapeStyle

    /// Creates branding with a **solid color** background, rendered with the system's native,
    /// StandBy-adaptive Live Activity background.
    public init(
        logo: Image? = nil,
        background: Color = Color.black.opacity(0.85),
        textColor: some ShapeStyle = Color.white,
        progressCompleteStyle: some ShapeStyle = Color.white,
        progressIncompleteStyle: some ShapeStyle = Color(white: 0.4)
    ) {
        self.logo = logo
        self.background = TemplateBackground(color: background)
        self.textColor = AnyShapeStyle(textColor)
        self.progressCompleteStyle = AnyShapeStyle(progressCompleteStyle)
        self.progressIncompleteStyle = AnyShapeStyle(progressIncompleteStyle)
    }

    /// Creates branding with a **gradient / other `ShapeStyle`** background, drawn directly (renders
    /// exactly as given; not system-dimmed in StandBy / Always-On Display).
    public init(
        logo: Image? = nil,
        background: some ShapeStyle,
        textColor: some ShapeStyle = Color.white,
        progressCompleteStyle: some ShapeStyle = Color.white,
        progressIncompleteStyle: some ShapeStyle = Color(white: 0.4)
    ) {
        self.logo = logo
        self.background = TemplateBackground(style: background)
        self.textColor = AnyShapeStyle(textColor)
        self.progressCompleteStyle = AnyShapeStyle(progressCompleteStyle)
        self.progressIncompleteStyle = AnyShapeStyle(progressIncompleteStyle)
    }
}
#endif
