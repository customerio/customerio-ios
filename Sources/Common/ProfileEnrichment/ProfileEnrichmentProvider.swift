import Foundation

/// Provides attributes to be merged into the identify payload.
/// Implementations should return only primitive values (String, Number, Bool) so they can be safely serialized.
/// Keys are reserved per provider.
public protocol ProfileEnrichmentProvider: AnyObject {
    /// Returns attributes to merge into the profile on identify. Return nil when there is nothing to add.
    func getProfileEnrichmentAttributes() -> [String: Any]?
}
