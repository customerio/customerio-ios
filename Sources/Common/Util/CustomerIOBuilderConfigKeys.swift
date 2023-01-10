import Foundation

struct CustomerIOBuilderConfigKeys {

    struct Environment {
        static let siteId = "siteId"
        static let apiKey = "apiKey"
        static let region = "region"
    }

    struct Config {
        static let trackingApiUrl = "trackingApiUrl"
        static let autoTrackDeviceAttributes = "autoTrackDeviceAttributes"
        static let logLevel = "logLevel"
        static let autoTrackPushEvents = "autoTrackPushEvents"
        static let backgroundQueueMinNumberOfTasks = "backgroundQueueMinNumberOfTasks"
        static let backgroundQueueSecondsDelay = "backgroundQueueSecondsDelay"
    }

}
