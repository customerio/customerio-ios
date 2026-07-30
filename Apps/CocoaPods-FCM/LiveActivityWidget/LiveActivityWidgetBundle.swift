import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

/// Widget bundle for the CocoaPods sample app's Live Activities.
///
/// Both widgets are SDK-provided templates — the app only supplies branding. This exists to prove a
/// CocoaPods integration can render Customer.io Live Activities without writing any widget UI, and
/// that the `CustomerIOLiveActivities*` pods resolve alongside the rest of the SDK.
@main
struct LiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            CIOSegmentsLiveActivity(branding: CIOSegmentsBranding())
            CIOCountdownTimerLiveActivity(branding: CIOCountdownTimerBranding())
        }
    }
}
