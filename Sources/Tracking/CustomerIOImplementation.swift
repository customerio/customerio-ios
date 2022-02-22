import Foundation

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.
 You must have an instance of `CustomerIO` to use the features of the SDK.

 To get an instance, you have 2 options:
 1. Use the already provided singleton shared instance: `CustomerIO.instance`.
 This method is provided for convenience and is the easiest way to get started.

 2. Create your own instance: `CustomerIO(siteId: "XXX", apiKey: "XXX", region: Region.US)`
 This method is recommended for code bases containing
 automated tests, dependency injection, or sending data to multiple Workspaces.
 */
public class CustomerIOImplementation: CustomerIOInstance {
    public var siteId: String? {
        _siteId
    }

    private let _siteId: String

    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private var sdkConfigStore: SdkConfigStore
    private var profileStore: ProfileStore
    private var hooks: HooksManager
    private let logger: Logger

    static var autoScreenViewBody: (() -> [String: Any])?

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init(siteId: String) {
        self._siteId = siteId

        let diGraph = DITracking.getInstance(siteId: siteId)

        self.backgroundQueue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.sdkConfigStore = diGraph.sdkConfigStore
        self.profileStore = diGraph.profileStore
        self.hooks = diGraph.hooksManager
        self.logger = diGraph.logger
    }

    /**
     Configure the Customer.io SDK.

     This will configure the given non-singleton instance of CustomerIO.
     Configuration changes will only impact this 1 instance of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
     $0.trackingApiUrl = "https://example.com"
     }
     ```
     */
    public func config(_ handler: (inout SdkConfig) -> Void) {
        var configToModify = sdkConfigStore.config

        handler(&configToModify)

        sdkConfigStore.config = configToModify

        if sdkConfigStore.config.autoTrackScreenViews {
            setupAutoScreenviewTracking()
        }
    }

    public var profileAttributes: [String: Any] {
        get {
            [:]
        }
        set {
            guard let existingProfileIdentifier = profileStore.identifier else {
                return
            }
            identify(identifier: existingProfileIdentifier, body: StringAnyEncodable(newValue))
        }
    }
    
    public var deviceAttributes: [String: Any] {
        get {
            [:]
        }
        set {
            hooks.deviceAttributesHooks.forEach{ hook in
                hook.customDeviceAttributesAdded(attributes: StringAnyEncodable(newValue))
            }
        }
    }

    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody
    ) {
        logger.info("identify profile \(identifier)")

        let currentlyIdentifiedProfileIdentifier = profileStore.identifier
        let isChangingIdentifiedProfile = currentlyIdentifiedProfileIdentifier != nil &&
            currentlyIdentifiedProfileIdentifier != identifier
        let isFirstTimeIdentifying = currentlyIdentifiedProfileIdentifier == nil

        if let currentlyIdentifiedProfileIdentifier = currentlyIdentifiedProfileIdentifier,
           isChangingIdentifiedProfile {
            logger.info("changing profile from id \(currentlyIdentifiedProfileIdentifier) to \(identifier)")

            logger.debug("running hooks changing profile from \(currentlyIdentifiedProfileIdentifier) to \(identifier)")
            hooks.profileIdentifyHooks.forEach { hook in
                hook.beforeIdentifiedProfileChange(oldIdentifier: currentlyIdentifiedProfileIdentifier,
                                                   newIdentifier: identifier)
            }
        }

        let jsonBodyString = jsonAdapter.toJsonString(body, encoder: nil)
        logger.debug("identify profile attributes \(jsonBodyString ?? "none")")

        let queueTaskData = IdentifyProfileQueueTaskData(identifier: identifier,
                                                         attributesJsonString: jsonBodyString)

        // If SDK previously identified profile X and X is being identified again, no use blocking the queue
        // with a queue group.
        var queueGroupStart: QueueTaskGroup? = .identifiedProfile(identifier: identifier)
        if !isChangingIdentifiedProfile {
            queueGroupStart = nil
        }

        let queueStatus = backgroundQueue.addTask(type: QueueTaskType.identifyProfile.rawValue,
                                                  data: queueTaskData,
                                                  groupStart: queueGroupStart)

        // don't modify the state of the SDK until we confirm we added a background queue task successfully.
        // XXX: better handle scenario when adding task to queue is not successful
        guard queueStatus.success else {
            // XXX: better handle scenario when adding task to queue is not successful
            logger.debug("failed to enqueue identify task")
            return
        }

        logger.debug("storing identifier on device storage \(identifier)")
        profileStore.identifier = identifier

        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            logger.debug("running hooks profile identified \(identifier)")
            hooks.profileIdentifyHooks.forEach { hook in
                hook.profileIdentified(identifier: identifier)
            }
        }
    }

    public func clearIdentify() {
        logger.info("clearing identified profile")

        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            return
        }

        logger.debug("deleting profile info from device storage")
        profileStore.identifier = nil

        logger.debug("running hooks: profile stopped being identified \(currentlyIdentifiedProfileIdentifier)")
        hooks.profileIdentifyHooks.forEach { hook in
            hook.profileStoppedBeingIdentified(oldIdentifier: currentlyIdentifiedProfileIdentifier)
        }
    }

    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody?
    ) {
        trackEvent(type: .event, name: name, data: data)
    }

    public func screen(name: String, data: [String: Any]) {
        screen(name: name, data: StringAnyEncodable(data))
    }

    public func screen<RequestBody: Encodable>(
        name: String,
        data: RequestBody
    ) {
        trackEvent(type: .screen, name: name, data: data)
    }
}

extension CustomerIOImplementation {
    private func trackEvent<RequestBody: Encodable>(type: EventType,
                                                    name: String,
                                                    data: RequestBody?) {
        let eventTypeDescription = (type == .screen) ? "track screen view event" : "track event"

        logger.info("\(eventTypeDescription) \(name)")

        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            // XXX: when we have anonymous profiles in SDK,
            // we can decide to not ignore events when a profile is not logged yet.
            logger.info("ignoring \(eventTypeDescription) \(name) because no profile currently identified")
            return
        }

        // JSON encoding with `data = nil` returns `"data":null`.
        // API returns 400 "event data must be a hash" for that. `"data":{}` is a better default.
        let data: AnyEncodable = (data == nil) ? AnyEncodable(EmptyRequestBody()) : AnyEncodable(data)

        let requestBody = TrackRequestBody(type: type, name: name, data: data, timestamp: Date())
        guard let jsonBodyString = jsonAdapter.toJsonString(requestBody, encoder: nil) else {
            logger.error("attributes provided for \(eventTypeDescription) \(name) failed to JSON encode.")
            return
        }
        logger.debug("\(eventTypeDescription) attributes \(jsonBodyString)")

        let queueData = TrackEventQueueTaskData(identifier: currentlyIdentifiedProfileIdentifier,
                                                attributesJsonString: jsonBodyString)

        // XXX: better handle scenario when adding task to queue is not successful
        _ = backgroundQueue.addTask(type: QueueTaskType.trackEvent.rawValue,
                                    data: queueData,
                                    blockingGroups: [
                                        .identifiedProfile(identifier: currentlyIdentifiedProfileIdentifier)
                                    ])
    }
}
