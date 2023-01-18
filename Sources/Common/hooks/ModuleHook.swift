import Foundation

/// Provider constructs new instances of hooks when requested.
/// We want to try and limit singletons in this class to avoid circular dependencies
/// from initializing so many classes. So, initialize instances when requested.
public protocol ModuleHookProvider: AutoMockable {
    var profileIdentifyHook: ProfileIdentifyHook? { get }
    var queueRunnerHook: QueueRunnerHook? { get }
    var screenTrackingHook: ScreenTrackingHook? { get }
}

// hooks all dealing with events related to profiles being identified.
public protocol ProfileIdentifyHook: AutoMockable {
    /// called when switching to a new profile. Only called when
    /// `oldIdentifier != newIdentifier`
    func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String)
    /// called when a profile is newly identified in the SDK.
    func profileIdentified(identifier: String)
    /// profile previously identified has stopped being identified.
    /// called before finishing the process of deleting which means you can still
    /// retrieve the identifier from SDK storage.
    func beforeProfileStoppedBeingIdentified(oldIdentifier: String)
}

// When a module wants to run background queue tasks, they implement this hook.
public protocol QueueRunnerHook: AutoMockable {
    /// called from background queue in `Tracking` module.
    /// return `true` if the `task` belongs to that module.
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) -> Bool
}

// Hook for when a screen view track event is sent
public protocol ScreenTrackingHook: AutoMockable {
    func screenViewed(name: String)
}
