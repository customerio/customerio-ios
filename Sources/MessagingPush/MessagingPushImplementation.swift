import CioTracking
import Foundation
import UIKit

internal class MessagingPushImplementation: MessagingPushInstance {
    
    private let profileStore: ProfileStore
    private let backgroundQueue: Queue
    private var globalDataStore: GlobalDataStore
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private var sdkConfigStore: SdkConfigStore
    
    /// testing init
    internal init(
        profileStore: ProfileStore,
        backgroundQueue: Queue,
        globalDataStore: GlobalDataStore,
        jsonAdapter : JsonAdapter,
        logger: Logger,
        sdkConfigStore : SdkConfigStore
    ) {
        self.profileStore = profileStore
        self.backgroundQueue = backgroundQueue
        self.globalDataStore = globalDataStore
        self.logger = logger
        self.sdkConfigStore = sdkConfigStore
        self.jsonAdapter = jsonAdapter
    }

    init(siteId: String) {
        let diGraph = DITracking.getInstance(siteId: siteId)

        self.profileStore = diGraph.profileStore
        self.jsonAdapter = diGraph.jsonAdapter
        self.backgroundQueue = diGraph.queue
        self.globalDataStore = diGraph.globalDataStore
        self.logger = diGraph.logger
        self.sdkConfigStore = diGraph.sdkConfigStore
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        addDeviceAttributes(deviceToken: deviceToken)
    }
    
    private func addDeviceAttributes(deviceToken : String, customAttributes : [String: String]? = nil) {
        
        logger.info("registering device token \(deviceToken)")
        logger.debug("storing device token to device storage \(deviceToken)")
        // no matter what, save the device token for use later. if a customer is identified later,
        // we can reference the token and register it to a new profile.
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            logger.info("no profile identified, so not registering device token to a profile")
            return
        }
        
        deviceAttributes(deviceToken: deviceToken) { attributes in
            var deviceAttributes = attributes ?? customAttributes
            if let customDeviceAttributes = customAttributes, let defaultDeviceAttributes = attributes {
                deviceAttributes = defaultDeviceAttributes.merging(customDeviceAttributes) { $1 }
            }
            _ = self.backgroundQueue.addTask(type: QueueTaskType.registerPushToken.rawValue,
                                             data: RegisterPushNotificationQueueTaskData(deviceToken: deviceToken, profileIdentifier: identifier,
                                                                                    lastUsed: Date(), attributes: deviceAttributes),
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
    
    private func deviceAttributes(deviceToken : String, completionHandler : @escaping([String: String]?) -> Void) {
        
        if !sdkConfigStore.config.autoTrackDeviceAttributes {
            completionHandler(nil)
            return
        }
        #if canImport(UIKit)
        let deviceOS = DeviceInfo.osInfo.value
        let deviceModel = DeviceInfo.deviceInfo.value
        let appVersion = DeviceInfo.customerAppVersion.value
        let sdkVersion = DeviceInfo.sdkVersion.value
        let deviceLocale = DeviceInfo.deviceLocale.value.replacingOccurrences(of: "_", with: "-")
        
        pushSubscribed { isSubscribed in
            let deviceAttributes = ["deviceOs": deviceOS,
                                    "deviceModel": deviceModel,
                                    "appVersion": appVersion,
                                    "cioSdkVersion": sdkVersion,
                                    "deviceLocale": deviceLocale,
                                    "pushSubscribed": isSubscribed]
            completionHandler(deviceAttributes)
        }
        #endif
    }
    
    private func pushSubscribed(completion: @escaping(String) -> Void) {
        let current = UNUserNotificationCenter.current()
        
        current.getNotificationSettings(completionHandler: { (settings) in
            if settings.authorizationStatus == .authorized {
                completion("true")
                return
            }
            completion("false")
        })
    }
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


extension MessagingPushImplementation : DeviceAttributesHook {
    func customDeviceAttributesAdded(attributes : [String : String]) {
        guard let deviceToken = globalDataStore.pushDeviceToken else { return }
        addDeviceAttributes(deviceToken: deviceToken, customAttributes: attributes)
    }
}
