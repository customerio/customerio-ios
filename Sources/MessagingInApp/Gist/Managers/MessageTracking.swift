import Foundation

/// Tracking data for a single anonymous message
struct MessageTracking: Codable {
    var timesShown: Int
    var dismissed: Bool
    var nextShowTime: Double?

    init(timesShown: Int = 0, dismissed: Bool = false, nextShowTime: Double? = nil) {
        self.timesShown = timesShown
        self.dismissed = dismissed
        self.nextShowTime = nextShowTime
    }
}

/// Container for all message tracking data
struct MessagesTrackingData: Codable {
    var tracking: [String: MessageTracking]

    init(tracking: [String: MessageTracking] = [:]) {
        self.tracking = tracking
    }
}
