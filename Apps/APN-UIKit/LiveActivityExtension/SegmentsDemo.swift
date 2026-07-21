#if os(iOS)
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

/// Branding preset for the SDK's shared `CIOSegmentsLiveActivity` template, styled as the "Chica"
/// food-delivery brand, plus previews walking the delivery states.
@available(iOS 16.2, *)
enum SegmentsDemoBranding {
    /// Food-delivery brand: warm orange **gradient** background (drawn directly) + a bundled logo.
    static let chica = CIOSegmentsBranding(
        logo: Image("chica-logo"),
        background: LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.29, blue: 0.03), // #FF4A07
                Color(red: 1.00, green: 0.53, blue: 0.00) // #FF8800
            ],
            startPoint: UnitPoint(x: 0, y: 0.41), // ≈ 100.37°
            endPoint: UnitPoint(x: 1, y: 0.59)
        ),
        textColor: .white,
        progressCompleteStyle: .white.opacity(0.8),
        progressIncompleteStyle: .white.opacity(0.5) // #FFFFFF80
    )

    /// The preset compiled into the live widget.
    static let active = chica
}

// MARK: - Previews (delivery states)

#Preview("Segments · Chica (food)", as: .content, using: CIOSegmentsAttributes(header: "Chica")) {
    CIOSegmentsLiveActivity(branding: SegmentsDemoBranding.chica)
} contentStates: {
    CIOSegmentsAttributes.ContentState(status: "Order placed", substatus: "We got your order", segmentsTotal: 4, segmentsComplete: 1, trailingText: "1/4")
    CIOSegmentsAttributes.ContentState(status: "Preparing your order", substatus: "Your food is being cooked", segmentsTotal: 4, segmentsComplete: 2, trailingText: "12 min")
    CIOSegmentsAttributes.ContentState(status: "Out for delivery", substatus: "Arriving soon", segmentsTotal: 4, segmentsComplete: 3, trailingText: "5 min")
    CIOSegmentsAttributes.ContentState(status: "Delivered", substatus: "Enjoy your meal!", segmentsTotal: 4, segmentsComplete: 4, trailingText: "Done")
}
#endif
