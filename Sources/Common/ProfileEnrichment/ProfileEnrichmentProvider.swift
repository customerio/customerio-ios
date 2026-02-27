import Foundation

/// Provides attributes to be merged into the identify payload.
/// Implementations should return only primitive values (String, Number, Bool) so they can be safely serialized.
/// Keys are reserved per provider.
public protocol ProfileEnrichmentProvider: AnyObject {
    /// Returns attributes to merge into the profile on identify. Return nil when there is nothing to add.
    func getProfileEnrichmentAttributes() -> [String: Any]?

    /// Clears any cached context for the current profile. Called synchronously during analytics reset
    /// so that subsequent identify() sees clean state (e.g. no stale location from the previous profile).
    /// Providers with no cached state can use the default no-op implementation.
    func resetContext()
}

public extension ProfileEnrichmentProvider {
    /// Default no-op for providers that do not hold profile-scoped context.
    func resetContext() {}
}
