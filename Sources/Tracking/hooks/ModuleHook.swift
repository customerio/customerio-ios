import Foundation

/// Provider constructs an instance of `ModuleHook` when called.
public protocol ModuleHookProvider {
    var hook: ModuleHook? { get }
}

public protocol ModuleHook {
    func beforeNewProfileIdentified(oldIdentifier: String, newIdentifier: String)
    /// called when a profile is newly identified in the SDK.
    func profileIdentified(identifier: String)
    /// called from background queue. allows SDK to run a given task if that task was created in the SDK.
    /// return `true` if the hook will handle running that given task.
    func runQueueTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool
}

public protocol HooksManager {
    func add(key: HookModules, provider: ModuleHookProvider)
    var hooks: [ModuleHook] { get }
}

public enum HookModules: String {
    case messagingPush
}

typealias Hooks = [ModuleHook]

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

    public var hooks: [ModuleHook] {
        hookProviders.filter { $0.value.hook != nil }.map { $0.value.hook! }
    }
}
