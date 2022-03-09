import CioTracking
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

internal class MessagingPushImplementation: MessagingPushInstance {
    private let siteId: SiteId
    private let profileStore: ProfileStore
    private let backgroundQueue: Queue
    private var globalDataStore: GlobalDataStore
    private let logger: Logger
    private let sdkConfigStore: SdkConfigStore
    private let jsonAdapter: JsonAdapter

    /// testing init
    internal init(
        siteId: SiteId,
        profileStore: ProfileStore,
        backgroundQueue: Queue,
        globalDataStore: GlobalDataStore,
        logger: Logger,
        sdkConfigStore: SdkConfigStore,
        jsonAdapter: JsonAdapter
    ) {
        self.siteId = siteId
        self.profileStore = profileStore
        self.backgroundQueue = backgroundQueue
        self.globalDataStore = globalDataStore
        self.logger = logger
        self.sdkConfigStore = sdkConfigStore
        self.jsonAdapter = jsonAdapter
    }

    init(siteId: String) {
        self.siteId = siteId
        let diGraph = DITracking.getInstance(siteId: siteId)

        self.profileStore = diGraph.profileStore
        self.backgroundQueue = diGraph.queue
        self.globalDataStore = diGraph.globalDataStore
        self.logger = diGraph.logger
        self.sdkConfigStore = diGraph.sdkConfigStore
        self.jsonAdapter = diGraph.jsonAdapter
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        addDeviceAttributes(deviceToken: deviceToken)
    }
    /**
     Adds device default and custom attributes and registers device token.
     */
    private func addDeviceAttributes(deviceToken: String, customAttributes: [String: Any]? = nil) {
        logger.info("registering device token \(deviceToken)")
        logger.debug("storing device token to device storage \(deviceToken)")
        // no matter what, save the device token for use later. if a customer is identified later,
        // we can reference the token and register it to a new profile.
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            logger.info("no profile identified, so not registering device token to a profile")
            return
        }
        getDefaultDeviceAttributes {attributes in
            var deviceAttributes = attributes ?? [:]
            if let customDeviceAttributes = customAttributes {
                deviceAttributes = deviceAttributes.mergeWith(customDeviceAttributes)
            }
            let body = StringAnyEncodable(deviceAttributes)
            let data: AnyEncodable = AnyEncodable(body)
            let requestBody = RegisterDeviceRequest(device: Device(token: deviceToken,
                                                                   lastUsed: Date(),
                                                                   attributes: data))

            guard let jsonBodyString = self.jsonAdapter.toJsonString(requestBody, encoder: nil) else {
                return
            }
            let queueTaskData = RegisterPushNotificationQueueTaskData(profileIdentifier: identifier,
                                                    attributesJsonString: jsonBodyString)

            _ = self.backgroundQueue.addTask(type: QueueTaskType.registerPushToken.rawValue,
                                             data: queueTaskData,
                                        groupStart: .registeredPushToken(token: deviceToken),
                                        blockingGroups: [.identifiedProfile(identifier: identifier)])
        }
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        logger.info("deleting device token request made")

        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            logger.info("no device token exists so ignoring request to delete")
            return // no device token to delete, ignore request
        }
        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        guard let identifiedProfileId = profileStore.identifier else {
            logger.info("no profile identified so not removing device token from profile")
            return // no profile to delete token from, ignore request
        }

        _ = backgroundQueue.addTask(type: QueueTaskType.deletePushToken.rawValue,
                                    data: DeletePushNotificationQueueTaskData(profileIdentifier: identifiedProfileId,
                                                                              deviceToken: existingDeviceToken),
                                    blockingGroups: [
                                        .registeredPushToken(token: existingDeviceToken),
                                        .identifiedProfile(identifier: identifiedProfileId)
                                    ])
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        logger.info("push metric \(event.rawValue)")

        logger.debug("delivery id \(deliveryID) device token \(deviceToken)")

        _ = backgroundQueue.addTask(type: QueueTaskType.trackPushMetric.rawValue,
                                    data: MetricRequest(deliveryId: deliveryID, event: event, deviceToken: deviceToken,
                                                        timestamp: Date()))
    }
    func getDefaultDeviceAttributes(completionHandler: @escaping([String: Any]?) -> Void) {
        if !sdkConfigStore.config.autoTrackDeviceAttributes {
            completionHandler(nil)
            return
        }
        let deviceDetail = DeviceInfo()
        let deviceOS = deviceDetail.osInfo
        let deviceModel = deviceDetail.deviceInfo
        let appVersion = deviceDetail.customerAppVersion
        let sdkVersion = deviceDetail.sdkVersion
        let deviceLocale = deviceDetail.deviceLocale.replacingOccurrences(of: "_", with: "-")
        deviceDetail.pushSubscribed { isSubscribed in
            let deviceAttributes = ["device_os": deviceOS,
                                    "device_model": deviceModel,
                                    "app_version": appVersion,
                                    "cio_sdk_version": sdkVersion,
                                    "device_locale": deviceLocale,
                                    "push_subscribed": String(isSubscribed)]
            completionHandler(deviceAttributes)
        }
    }

    #if canImport(UserNotifications)
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    public func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        logger.info("did recieve notification request. Checking if message was a rich push sent from Customer.io...")
        logger.debug("notification request: \(request.content.userInfo)")

        if sdkConfigStore.config.autoTrackPushEvents,
           let deliveryID: String = request.content.userInfo["CIO-Delivery-ID"] as? String,
           let deviceToken: String = request.content.userInfo["CIO-Delivery-Token"] as? String {
            logger.info("automatically tracking push metric: delivered")
            logger.debug("parsed deliveryId \(deliveryID), deviceToken: \(deviceToken)")

            trackMetric(deliveryID: deliveryID, event: .delivered, deviceToken: deviceToken)
        }

        guard let pushContent = PushContent.parse(notificationContent: request.content,
                                                  jsonAdapter: jsonAdapter)
        else {
            // push does not contain a CIO rich payload, so end early
            logger.info("the notification was not sent by Customer.io. Ignoring notification request.")
            return false
        }

        logger
            .info("""
            the notification was sent by Customer.io.
            Parsing notification request to display rich content such as images, deep links, etc.
            """)
        logger.debug("push content: \(pushContent)")

        RichPushRequestHandler.shared.startRequest(request, content: pushContent, siteId: siteId,
                                                   completionHandler: contentHandler)

        return true
    }

    /**
     iOS OS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    public func serviceExtensionTimeWillExpire() {
        logger.info("notification service time will expire. Stopping all notification requests early.")

        RichPushRequestHandler.shared.stopAll()
    }

    /**
     A push notification was interacted with.

     - returns: If the SDK called the completion handler for you indicating if the SDK took care of the request or not.
     */
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        if sdkConfigStore.config.autoTrackPushEvents {
            var pushMetric = Metric.delivered

            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                pushMetric = Metric.opened
            }

            trackMetric(notificationContent: response.notification.request.content, event: pushMetric)
        }

        // Time to handle rich push notifications.
        guard let pushContent = PushContent.parse(notificationContent: response.notification.request.content,
                                                  jsonAdapter: jsonAdapter)
        else {
            // push does not contain a CIO rich payload, so end early
            return false
        }

        cleanup(pushContent: pushContent)

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: // push notification was touched.
            if let deepLinkurl = pushContent.deepLink {
                UIApplication.shared.open(url: deepLinkurl)

                completionHandler()

                return true
            }
        default: break
        }

        return false
    }

    func trackMetric(
        notificationContent: UNNotificationContent,
        event: Metric
    ) {
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String,
              let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String
        else {
            return
        }

        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    private func cleanup(pushContent: PushContent) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}

extension MessagingPushImplementation: ProfileIdentifyHook {
    // When a new profile is identified, delete token from previously identified profile for
    // privacy and messaging releveance reasons. We only want to send messages to the currently
    // identified profile.
    func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String) {
        logger.debug("hook: deleting device before identifying new profile")

        deleteDeviceToken()
    }

    // When a profile is identified, try to automatically register a device token to them if there is one assigned
    // to this device
    func profileIdentified(identifier: String) {
        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            logger.debug("hook: no push token stored so not automatically registering token to profile")
            return
        }

        logger.debug("hook: automatically registering token to profile identified. token: \(existingDeviceToken)")

        registerDeviceToken(existingDeviceToken)
    }

    // stop sending push to a profile that is no longer identified
    func profileStoppedBeingIdentified(oldIdentifier: String) {
        logger.debug("hook: deleting device token from profile no longer identified")

        deleteDeviceToken()
    }
}

extension MessagingPushImplementation: DeviceAttributesHook {
    // Adds custom device attributes to background queue and sends to workspace
    func customDeviceAttributesAdded(attributes: [String: Any]) {
        guard let deviceToken = globalDataStore.pushDeviceToken else { return }
        addDeviceAttributes(deviceToken: deviceToken, customAttributes: attributes)
    }
}
