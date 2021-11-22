import Foundation

/// Provider constructs an instance of `ModuleHook` when called.
public protocol ModuleHookProvider {
    var profileIdentifyHook: ProfileIdentifyHook? { get }
    var queueRunnerHook: QueueRunnerHook? { get }
}

public protocol ProfileIdentifyHook {
    func beforeNewProfileIdentified(oldIdentifier: String, newIdentifier: String)
    /// called when a profile is newly identified in the SDK.
    func profileIdentified(identifier: String)
}

public protocol QueueRunnerHook {
    /// called from background queue. allows SDK to run a given task if that task was created in the SDK.
    /// return `true` if the hook will handle running that given task.
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool
}

public protocol HooksManager {
    func add(key: HookModules, provider: ModuleHookProvider)
    var profileIdentifyHooks: [ProfileIdentifyHook] { get }
    var queueRunnerHooks: [QueueRunnerHook] { get }
}

public enum HookModules: String {
    case messagingPush
}

/**
 Singleton because we are storing objects in-memory set at runtime.

 As long as `ModuleHookProvider` subclasses are limiting thier use
 of singletons, it's OK for this class to be one.
 */
// sourcery: InjectRegister = "HooksManager"
// sourcery: InjectSingleton
public class CioHooksManager: HooksManager {
    private var hookProviders: [HookModules: ModuleHookProvider] = [:]

    /// using key/value pairs enforces that there is only 1 hook provider for each
    /// SDK without having duplicates.
    public func add(key: HookModules, provider: ModuleHookProvider) {
        hookProviders[key] = provider
    }

    public var profileIdentifyHooks: [ProfileIdentifyHook] {
        hookProviders.filter { $0.value.profileIdentifyHook != nil }.map { $0.value.profileIdentifyHook! }
    }

    public var queueRunnerHooks: [QueueRunnerHook] {
        hookProviders.filter { $0.value.queueRunnerHook != nil }.map { $0.value.queueRunnerHook! }
    }
}
