import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

@main
struct LiveActivityExtensionBundle: WidgetBundle {
    init() {
        CIOLiveActivitiesTemplates.configure(
            appGroup: "group.io.customer.ios-sample.apn-spm.APN-UIKit.cio",
            branding: CIOActivityBranding(name: "Next Level Sports", logoKey: "NL-Logo", accentColor: "#F26726")
        )
    }

    var body: some Widget {
        CIOAuctionBidLiveActivity()
        CIOCountdownTimerLiveActivity()
        CIODeliveryTrackingLiveActivity()
        CIOFlightStatusLiveActivity()
        CIOLiveScoreLiveActivity()
        if #available(iOS 18, *) {
            CIOLiveScoreWatchLiveActivity()
        }
    }
}
