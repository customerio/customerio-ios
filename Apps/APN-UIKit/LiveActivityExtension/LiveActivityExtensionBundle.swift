//
//  LiveActivityExtensionBundle.swift
//  LiveActivityExtension
//
//  Created by Holly Schilling on 6/24/26.
//

import CioLiveActivities_Templates
import SwiftUI
import WidgetKit

@main
struct LiveActivityExtensionBundle: WidgetBundle {
    
    init() {
        CIOLiveActivitiesTemplates.configure(appGroup: "group.io.customer.ios-sample.apn-spm.APN-UIKit.cio")
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
