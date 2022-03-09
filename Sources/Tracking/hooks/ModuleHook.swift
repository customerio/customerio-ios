import Foundation

/// Provider constructs new instances of hooks when requested.
/// We want to try and limit singletons in this class to avoid circular dependencies
/// from initializing so many classes. So, initialize instances when requested.
public protocol ModuleHookProvider: AutoMockable {
    var profileIdentifyHook: ProfileIdentifyHook? { get }
    var queueRunnerHook: QueueRunnerHook? { get }
    var deviceAttributesHook: DeviceAttributesHook? {get}
}

// hooks all dealing with events related to profiles being identified.
public protocol ProfileIdentifyHook: AutoMockable {
    /// called when switching to a new profile. Only called when
    /// `oldIdentifier != newIdentifier`
    func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String)
    /// called when a profile is newly identified in the SDK.
    func profileIdentified(identifier: String)
    /// profile previously identified has stopped being identified.
    /// called only when there was a profile that was previously identified
    func profileStoppedBeingIdentified(oldIdentifier: String)
}

// When a module wants to run background queue tasks, they implement this hook.
public protocol QueueRunnerHook: AutoMockable {
    /// called from background queue in `Tracking` module.
    /// return `true` if the `task` belongs to that module.
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool
}

// Hook to send custom device attributes to workspace
public protocol DeviceAttributesHook: AutoMockable {
    func customDeviceAttributesAdded(attributes: [String: Any])
}
