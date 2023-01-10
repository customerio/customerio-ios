import Foundation

struct CustomerIOBuilderConfigKeys {
    enum Environment {
        static let siteId = "siteId"
        static let apiKey = "apiKey"
        static let region = "region"
    }

    enum Config {
        static let trackingApiUrl = "trackingApiUrl"
        static let autoTrackDeviceAttributes = "autoTrackDeviceAttributes"
        static let logLevel = "logLevel"
        static let autoTrackPushEvents = "autoTrackPushEvents"
        static let backgroundQueueMinNumberOfTasks = "backgroundQueueMinNumberOfTasks"
        static let backgroundQueueSecondsDelay = "backgroundQueueSecondsDelay"
    }
}
