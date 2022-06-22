import Foundation

public protocol HooksManager: AutoMockable {
    func add(key: HookModule, provider: ModuleHookProvider)
    var profileIdentifyHooks: [ProfileIdentifyHook] { get }
    var queueRunnerHooks: [QueueRunnerHook] { get }
    var deviceAttributesHooks: [DeviceAttributesHook] { get }
}

public enum HookModule: String {
    case tracking
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
    private var hookProviders: [HookModule: ModuleHookProvider] = [:]

    /// using key/value pairs enforces that there is only 1 hook provider for each
    /// SDK without having duplicates.
    public func add(key: HookModule, provider: ModuleHookProvider) {
        hookProviders[key] = provider
    }

    public var profileIdentifyHooks: [ProfileIdentifyHook] {
        hookProviders.filter { $0.value.profileIdentifyHook != nil }.map { $0.value.profileIdentifyHook! }
    }

    public var queueRunnerHooks: [QueueRunnerHook] {
        hookProviders.filter { $0.value.queueRunnerHook != nil }.map { $0.value.queueRunnerHook! }
    }

    // Checks all hooks available and provides hook for custom device attributes
    public var deviceAttributesHooks: [DeviceAttributesHook] {
        hookProviders.filter { $0.value.deviceAttributesHook != nil }.map { $0.value.deviceAttributesHook! }
    }
}
