import CioAnalytics
import CioInternalCommon

// To process pending tasks in background queue
// BGQ in each of the following methods refer to background queue
extension DataPipelineImplementation {
    func processAlreadyIdentifiedUser(identifier: String) {
        commonIdentifyProfile(userId: identifier)
    }

    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?) {
        var identifyEvent = IdentifyEvent(userId: identifier, traits: nil)
        identifyEvent.timestamp = timestamp
        if let traits = body {
            let jsonTraits = try? JSON(traits)
            identifyEvent.traits = jsonTraits
        }
        analytics.process(event: identifyEvent)
    }

    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        var screenEvent = ScreenEvent(title: name, category: nil)
        screenEvent.userId = identifier
        screenEvent.timestamp = timestamp
        if let jsonProperties = try? JSON(properties) {
            screenEvent.properties = jsonProperties
        }
        analytics.process(event: screenEvent)
    }

    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        var trackEvent = TrackEvent(event: name, properties: nil)
        trackEvent.userId = identifier
        trackEvent.timestamp = timestamp
        if let jsonProperties = try? JSON(properties) {
            trackEvent.properties = jsonProperties
        }
        analytics.process(event: trackEvent)
    }

    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String) {
        var trackDeleteEvent = TrackEvent(event: "Device Deleted", properties: nil)
        trackDeleteEvent.userId = identifier
        trackDeleteEvent.timestamp = timestamp
        let deviceDict: [String: Any] = ["device": ["token": token, "type": "ios"]]
        if let context = try? JSON(deviceDict) {
            trackDeleteEvent.context = context
        }
        analytics.process(event: trackDeleteEvent)
    }

    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]? = nil) {
        var trackRegisterTokenEvent = TrackEvent(event: "Device Created or Updated", properties: nil)
        trackRegisterTokenEvent.userId = identifier
        trackRegisterTokenEvent.timestamp = timestamp
        let tokenDict: [String: Any] = ["token": token, "type": "ios"]

        let deviceDict: [String: Any] = ["device": tokenDict]
        if let context = try? JSON(deviceDict) {
            trackRegisterTokenEvent.context = context
        }
        if let attributes = attributes, let attributes = try? JSON(attributes) {
            trackRegisterTokenEvent.properties = attributes
        }
        analytics.process(event: trackRegisterTokenEvent)
    }

    func processMetricsFromBGQ(token: String?, event: String, deliveryId: String, timestamp: String, metaData: [String: Any]) {
        var properties: [String: Any] = metaData.mergeWith([
            "metric": event,
            "deliveryId": deliveryId
        ])
        if let token = token {
            properties["recipient"] = token
        }
        var trackPushMetricEvent = TrackEvent(event: "Report Delivery Event", properties: try? JSON(properties))
        // anonymousId or userId is required in the payload for backend processing
        trackPushMetricEvent.anonymousId = deliveryId
        trackPushMetricEvent.timestamp = timestamp
        analytics.process(event: trackPushMetricEvent)
    }
}
