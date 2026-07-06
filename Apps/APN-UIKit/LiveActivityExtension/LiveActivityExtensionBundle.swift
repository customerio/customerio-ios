import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

@main
struct LiveActivityExtensionBundle: WidgetBundle {
    init() {
        CIOLiveActivitiesTemplates.configure(
            appGroup: "group.io.customer.ios-sample.apn-spm.APN-UIKit.cio",
            branding: CIOActivityBranding(
                name: "Chica's Chicken",
                logoKey: "chica_logo",
                backgroundColor: "#FFFFFF",
                textColor: "#0A2540"
            )
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
