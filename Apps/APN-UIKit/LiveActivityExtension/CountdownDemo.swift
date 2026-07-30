#if os(iOS)
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

/// Branding preset for the SDK's `CIOCountdownTimerLiveActivity` template, plus previews walking the
/// running → finished states.
@available(iOS 16.2, *)
enum CountdownDemoBranding {
    /// Flash-sale brand: violet→magenta **gradient** background (drawn) + a bolt SF Symbol logo.
    static let sale = CIOCountdownTimerBranding(
        logo: Image(systemName: "bolt.fill"),
        background: LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.13, blue: 0.71), // #5B21B6
                Color(red: 0.62, green: 0.09, blue: 0.30) // #9D174D
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        textColor: .white
    )

    /// The preset compiled into the live widget.
    static let active = sale
}

// MARK: - Previews (running → finished)

#Preview("Countdown · running", as: .content, using: CIOCountdownTimerAttributes(header: "Summer Sale")) {
    CIOCountdownTimerLiveActivity(branding: CountdownDemoBranding.sale)
} contentStates: {
    CIOCountdownTimerAttributes.ContentState(title: "Flash sale ends in", statusMessage: "Up to 50% off sitewide", endTime: EpochSecondsDate(Date().addingTimeInterval(7200)))
    CIOCountdownTimerAttributes.ContentState(title: "Almost gone!", statusMessage: "Final hour", endTime: EpochSecondsDate(Date().addingTimeInterval(600)))
    CIOCountdownTimerAttributes.ContentState(title: "Sale ended", statusMessage: "Thanks for shopping", endTime: nil)
}
#endif
