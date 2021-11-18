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

    private let diGraph: DITracking

    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private var profileStore: ProfileStore
    private var hooks: Hooks

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init(siteId: String) {
        self._siteId = siteId

        self.diGraph = DITracking.getInstance(siteId: siteId)

        self.backgroundQueue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.profileStore = diGraph.profileStore
        self.hooks = diGraph.hooksManager.hooks
    }

    /**
     Configure the Customer.io SDK.

     This will configure the given non-singleton instance of CustomerIO.
     Cofiguration changes will only impact this 1 instance of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
     $0.trackingApiUrl = "https://example.com"
     }
     ```
     */
    public func config(_ handler: (inout SdkConfig) -> Void) {
        var sdkConfigStore = diGraph.sdkConfigStore

        var configToModify = sdkConfigStore.config

        handler(&configToModify)

        sdkConfigStore.config = configToModify
    }

    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        jsonEncoder: JSONEncoder? = nil
    ) {
        if let currentlyIdentifiedProfileIdentifier = profileStore.identifier {
            messagingPush?.deletePushToken()

            hooks.forEach {
                $0.beforeNewProfileIdentified(oldIdentifier: currentlyIdentifiedProfileIdentifier,
                                              newIdentifier: identifier)
            }
        }

        let jsonBodyString = jsonAdapter.toJsonString(body, encoder: jsonEncoder)

        let queueTaskData = IdentifyProfileQueueTaskData(identifier: identifier,
                                                         attributesJsonString: jsonBodyString)
        let queueStatus = backgroundQueue.addTask(type: QueueTaskType.identifyProfile.rawValue, data: queueTaskData)

        // don't modify the state of the SDK until we confirm we added a background queue task successfully.
        if queueStatus.success {
            profileStore.identifier = identifier
        }

        hooks.forEach {
            $0.profileIdentified(identifier: identifier)
        }

        // TODO: after background queue fully implemented into the whole SDK (not just Tracking module) I see
        // this no longer being needed. This is currently the way for other SDKs (modules) in the project at runtime
        // to get informed about something happening but we plan on instead changing to runtime "hooks" between
        // the SDKs.
        // self.eventBus.post(.identifiedCustomer)
    }

    public func clearIdentify() {
        profileStore.identifier = nil
    }

    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody,
        jsonEncoder: JSONEncoder? = nil
    ) {
        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            // XXX: when we have anonymous profiles in SDK,
            // we can decide to not ignore events when a profile is not logged yet.
            return
        }

        let requestBody = TrackRequestBody(name: name, data: data, timestamp: Date())
        guard let jsonBodyString = jsonAdapter.toJsonString(requestBody, encoder: jsonEncoder) else {
            // XXX: log error for customer to debug their request body
            return
        }

        let queueData = TrackEventQueueTaskData(identifier: currentlyIdentifiedProfileIdentifier,
                                                attributesJsonString: jsonBodyString)

        // ignore if adding task was successful or not.
        // if not successful, it does not impact the state of the SDK so just ignore it.
        _ = backgroundQueue.addTask(type: QueueTaskType.trackEvent.rawValue, data: queueData)
    }
}
