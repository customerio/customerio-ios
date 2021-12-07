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
    }

    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        jsonEncoder: JSONEncoder? = nil
    ) {
        let currentlyIdentifiedProfileIdentifier = profileStore.identifier
        let isChangingIdentifiedProfile = currentlyIdentifiedProfileIdentifier != nil &&
            currentlyIdentifiedProfileIdentifier != identifier

        if let currentlyIdentifiedProfileIdentifier = currentlyIdentifiedProfileIdentifier,
           isChangingIdentifiedProfile {
            hooks.profileIdentifyHooks.forEach { hook in
                hook.beforeIdentifiedProfileChange(oldIdentifier: currentlyIdentifiedProfileIdentifier,
                                                   newIdentifier: identifier)
            }
        }

        let jsonBodyString = jsonAdapter.toJsonString(body, encoder: jsonEncoder)

        let queueTaskData = IdentifyProfileQueueTaskData(identifier: identifier,
                                                         attributesJsonString: jsonBodyString)
        let queueStatus = backgroundQueue.addTask(type: QueueTaskType.identifyProfile.rawValue, data: queueTaskData)

        // don't modify the state of the SDK until we confirm we added a background queue task successfully.
        // XXX: better handle scenario when adding task to queue is not successful
        if queueStatus.success {
            profileStore.identifier = identifier

            if currentlyIdentifiedProfileIdentifier == nil || isChangingIdentifiedProfile {
                hooks.profileIdentifyHooks.forEach { hook in
                    hook.profileIdentified(identifier: identifier)
                }
            }
        }
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

        // XXX: better handle scenario when adding task to queue is not successful
        _ = backgroundQueue.addTask(type: QueueTaskType.trackEvent.rawValue, data: queueData)
    }
}
