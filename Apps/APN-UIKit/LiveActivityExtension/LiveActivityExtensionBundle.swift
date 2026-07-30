import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

/// Widget bundle for the sample app's Live Activities.
///
/// `DeliveryActivityWidget` is an app-owned widget (the customer renders it themselves).
/// `CIOSegmentsLiveActivity` is an SDK-provided template the app just styles via branding — see
/// `SegmentsDemo` for the two branding presets.
@main
struct LiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            DeliveryActivityWidget()
            CIOSegmentsLiveActivity(branding: SegmentsDemoBranding.active)
            CIOCountdownTimerLiveActivity(branding: CountdownDemoBranding.active)
        }
    }
}
