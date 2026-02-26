import Foundation

// sourcery: InjectRegisterShared = "ProfileEnrichmentRegistry"
// sourcery: InjectSingleton
/// Thread-safe singleton registry of profile enrichment providers. Cleared on DIGraphShared.reset().
/// Public so the generated DI property `profileEnrichmentRegistry` is public and visible to Location/DataPipeline modules.
public final class ProfileEnrichmentRegistryImpl: ProfileEnrichmentRegistry {
    private let lock = NSLock()
    private var providers: [ProfileEnrichmentProvider] = []

    public init() {}

    public func register(_ provider: ProfileEnrichmentProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers.append(provider)
    }

    public func getAll() -> [ProfileEnrichmentProvider] {
        lock.lock()
        defer { lock.unlock() }
        return providers
    }
}
