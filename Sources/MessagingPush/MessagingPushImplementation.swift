import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

internal class MessagingPushImplementation: MessagingPushInstance {
    let siteId: SiteId
    let profileStore: ProfileStore
    let backgroundQueue: Queue
    var globalDataStore: GlobalDataStore
    let logger: Logger
    let sdkConfigStore: SdkConfigStore
    let jsonAdapter: JsonAdapter
    let deviceAttributesProvider: DeviceAttributesProvider
    let dateUtil: DateUtil
    let deviceInfo: DeviceInfo

    /// testing init
    internal init(
        siteId: SiteId,
        profileStore: ProfileStore,
        backgroundQueue: Queue,
        globalDataStore: GlobalDataStore,
        logger: Logger,
        sdkConfigStore: SdkConfigStore,
        jsonAdapter: JsonAdapter,
        deviceAttributesProvider: DeviceAttributesProvider,
        dateUtil: DateUtil,
        deviceInfo: DeviceInfo
    ) {
        self.siteId = siteId
        self.profileStore = profileStore
        self.backgroundQueue = backgroundQueue
        self.globalDataStore = globalDataStore
        self.logger = logger
        self.sdkConfigStore = sdkConfigStore
        self.jsonAdapter = jsonAdapter
        self.deviceAttributesProvider = deviceAttributesProvider
        self.dateUtil = dateUtil
        self.deviceInfo = deviceInfo
    }

    init(siteId: String) {
        self.siteId = siteId
        let diGraph = DIGraph.getInstance(siteId: siteId)

        self.profileStore = diGraph.profileStore
        self.backgroundQueue = diGraph.queue
        self.globalDataStore = diGraph.globalDataStore
        self.logger = diGraph.logger
        self.sdkConfigStore = diGraph.sdkConfigStore
        self.jsonAdapter = diGraph.jsonAdapter
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo
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
    private func addDeviceAttributes(deviceToken: String, customAttributes: [String: Any] = [:]) {
        logger.info("registering device token \(deviceToken)")
        logger.debug("storing device token to device storage \(deviceToken)")
        // no matter what, save the device token for use later. if a customer is identified later,
        // we can reference the token and register it to a new profile.
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            logger.info("no profile identified, so not registering device token to a profile")
            return
        }
        // OS name might not be available if running on non-apple product. We currently only support iOS for the SDK
        // and iOS should always be non-nil. Though, we are consolidating all Apple platforms under iOS but this check
        // is
        // required to prevent SDK execution for unsupported OS.
        if deviceInfo.osName == nil {
            logger.info("SDK being executed from unsupported OS. Ignoring request to register push token.")
            return
        }
        // Consolidate all Apple platforms under iOS
        let deviceOsName = "iOS"
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            let deviceAttributes = defaultDeviceAttributes.mergeWith(customAttributes)

            let encodableBody =
                StringAnyEncodable(deviceAttributes) // makes [String: Any] Encodable to use in JSON body.
            let requestBody = RegisterDeviceRequest(device: Device(
                token: deviceToken,
                platform: deviceOsName,
                lastUsed: self.dateUtil.now,
                attributes: encodableBody
            ))

            guard let jsonBodyString = self.jsonAdapter.toJsonString(requestBody) else {
                return
            }
            let queueTaskData = RegisterPushNotificationQueueTaskData(
                profileIdentifier: identifier,
                attributesJsonString: jsonBodyString
            )

            _ = self.backgroundQueue.addTask(
                type: QueueTaskType.registerPushToken.rawValue,
                data: queueTaskData,
                groupStart: .registeredPushToken(token: deviceToken),
                blockingGroups: [.identifiedProfile(identifier: identifier)]
            )
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

        _ = backgroundQueue.addTask(
            type: QueueTaskType.deletePushToken.rawValue,
            data: DeletePushNotificationQueueTaskData(
                profileIdentifier: identifiedProfileId,
                deviceToken: existingDeviceToken
            ),
            blockingGroups: [
                .registeredPushToken(token: existingDeviceToken),
                .identifiedProfile(identifier: identifiedProfileId)
            ]
        )
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

        _ = backgroundQueue.addTask(
            type: QueueTaskType.trackPushMetric.rawValue,
            data: MetricRequest(
                deliveryId: deliveryID,
                event: event,
                deviceToken: deviceToken,
                timestamp: Date()
            )
        )
    }

    #if canImport(UserNotifications)
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

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    internal func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
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
    func beforeProfileStoppedBeingIdentified(oldIdentifier: String) {
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
