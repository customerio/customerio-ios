import Common
import Foundation

/**
 Because of `CustomerIO.shared` being a singleton API, there is always a use-case
 of calling any of the public functions on `CustomerIO` class *before* the SDK has
 been initialized. To make this use case easy to handle, we separate the logic of
 the CustomerIO class into this class. Therefore, it's assumed that as long as
 there is an instance of `CustomerIOImplementation` present, the SDK has been
 initialized successfully.
 */
internal class CustomerIOImplementation: CustomerIOInstance {
    public var siteId: String? {
        _siteId
    }

    private let _siteId: String
    // This is the *only* strong reference to the DIGraph in the SDK.
    // It should be *locally* referenced in methods in of top-level classse in each module of this project.
    internal let diGraph: DIGraph

    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private var profileStore: ProfileStore
    private var hooks: HooksManager
    private let logger: Logger
    // strong reference to repository to prevent garbage collection as it runs tasks in async.
    //    private var cleanupRepository: CleanupRepository?

    static var autoScreenViewBody: (() -> [String: Any])?

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init(siteId: String, diGraph: DIGraph) {
        self._siteId = siteId
        self.diGraph = diGraph

        self.backgroundQueue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.profileStore = diGraph.profileStore
        self.hooks = diGraph.hooksManager
        self.logger = diGraph.logger
    }

    // Call from CustomerIO after SDK initialized. Not calling automatically
    // to make tests noisey.
    internal func postInitialize() {
        // TODO: enable some of these features.

        // Register Tracking module hooks now that the module is being initialized.
//        let hooksManager = diGraph.hooksManager
//        hooksManager.add(key: .tracking, provider: TrackingModuleHookProvider(siteId: siteId))
//
//        cleanupRepository = diGraph.cleanupRepository
//
//        // run cleanup in background to prevent locking the UI thread
//        threadUtil?.runBackground { [weak self] in
//            self?.cleanupRepository?.cleanup()
//            self?.cleanupRepository = nil
//        }
//
//        Self.shared.logger?
//            .info(
//                "Customer.io SDK \(SdkVersion.version) initialized and ready to use for site id: \(siteId)"
//            )
    }

    @available(iOSApplicationExtension, unavailable)
    internal func alterSdkFromConfig(_ config: SdkConfig) {
        if config.autoTrackDeviceAttributes {
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
            identify(identifier: existingProfileIdentifier, body: newValue)
        }
    }

    public var deviceAttributes: [String: Any] {
        get {
            [:]
        }
        set {
            hooks.deviceAttributesHooks.forEach { hook in
                hook.customDeviceAttributesAdded(attributes: newValue)
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
                hook.beforeIdentifiedProfileChange(
                    oldIdentifier: currentlyIdentifiedProfileIdentifier,
                    newIdentifier: identifier
                )
            }
        }

        // Custom attributes so do not modify keys in JSON string
        let jsonBodyString = jsonAdapter.toJsonString(body, convertKeysToSnakecase: false)
        logger.debug("identify profile attributes \(jsonBodyString ?? "none")")

        let queueTaskData = IdentifyProfileQueueTaskData(
            identifier: identifier,
            attributesJsonString: jsonBodyString
        )

        // If SDK previously identified profile X and X is being identified again, no use blocking the queue
        // with a queue group.
        var queueGroupStart: QueueTaskGroup? = .identifiedProfile(identifier: identifier)
        if !isChangingIdentifiedProfile {
            queueGroupStart = nil
        }

        let queueStatus = backgroundQueue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: queueTaskData,
            groupStart: queueGroupStart
        )

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

    public func identify(identifier: String, body: [String: Any]) {
        identify(identifier: identifier, body: StringAnyEncodable(body))
    }

    public func clearIdentify() {
        logger.info("clearing identified profile")

        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            return
        }

        logger.debug("running hooks: profile stopped being identified \(currentlyIdentifiedProfileIdentifier)")
        hooks.profileIdentifyHooks.forEach { hook in
            hook.beforeProfileStoppedBeingIdentified(oldIdentifier: currentlyIdentifiedProfileIdentifier)
        }

        logger.debug("deleting profile info from device storage")
        // remove device identifier from storage last so hooks can succeed.
        profileStore.identifier = nil
    }

    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody?
    ) {
        _ = trackEvent(type: .event, name: name, data: data)
    }

    public func track(name: String, data: [String: Any]) {
        track(name: name, data: StringAnyEncodable(data))
    }

    public func screen(name: String, data: [String: Any]) {
        screen(name: name, data: StringAnyEncodable(data))
    }

    public func screen<RequestBody: Encodable>(
        name: String,
        data: RequestBody
    ) {
        let eventWasTracked = trackEvent(type: .screen, name: name, data: data)

        if eventWasTracked {
            hooks.screenViewHooks.forEach { hook in
                hook.screenViewed(name: name)
            }
        }
    }
}

extension CustomerIOImplementation {
    // returns if an event was tracked. If no event was tracked (request was ignored), false will be returned.
    private func trackEvent<RequestBody: Encodable>(
        type: EventType,
        name: String,
        data: RequestBody?
    ) -> Bool {
        let eventTypeDescription = (type == .screen) ? "track screen view event" : "track event"

        logger.info("\(eventTypeDescription) \(name)")

        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            // XXX: when we have anonymous profiles in SDK,
            // we can decide to not ignore events when a profile is not logged yet.
            logger.info("ignoring \(eventTypeDescription) \(name) because no profile currently identified")
            return false
        }

        // JSON encoding with `data = nil` returns `"data":null`.
        // API returns 400 "event data must be a hash" for that. `"data":{}` is a better default.
        let data: AnyEncodable = (data == nil) ? AnyEncodable(EmptyRequestBody()) : AnyEncodable(data)

        let requestBody = TrackRequestBody(type: type, name: name, data: data, timestamp: Date())
        guard let jsonBodyString = jsonAdapter.toJsonString(requestBody) else {
            logger.error("attributes provided for \(eventTypeDescription) \(name) failed to JSON encode.")
            return false
        }
        logger.debug("\(eventTypeDescription) attributes \(jsonBodyString)")

        let queueData = TrackEventQueueTaskData(
            identifier: currentlyIdentifiedProfileIdentifier,
            attributesJsonString: jsonBodyString
        )

        // XXX: better handle scenario when adding task to queue is not successful
        _ = backgroundQueue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: queueData,
            blockingGroups: [
                .identifiedProfile(identifier: currentlyIdentifiedProfileIdentifier)
            ]
        )

        return true
    }
}
