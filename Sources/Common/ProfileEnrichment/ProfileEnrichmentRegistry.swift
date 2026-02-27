import Foundation

/// Thread-safe registry of profile enrichment providers. Used at identify time to merge provider attributes into the identify payload.
public protocol ProfileEnrichmentRegistry: AnyObject {
    /// Registers a provider. Call from module initialization (e.g. Location registers its provider).
    func register(_ provider: ProfileEnrichmentProvider)

    /// Returns all registered providers. Used by DataPipeline before identify to gather and merge attributes.
    func getAll() -> [ProfileEnrichmentProvider]
}
