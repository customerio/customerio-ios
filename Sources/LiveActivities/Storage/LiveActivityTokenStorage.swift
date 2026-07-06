import Foundation

/// Persists Live Activity token-registration state so unchanged tokens are not re-sent across
/// app launches.
///
/// Several kinds of entry share this store, distinguished by their key:
/// - push-to-start dedup signature, keyed by activity type — value `"<deviceToken>|<pushToStartToken>|<userId>"`.
/// - per-instance dedup signature, keyed by `"instance:<instanceUUID>"` — value `"<deviceToken>|<instanceToken>"`.
/// - persisted push-to-start token value, keyed by `"ptsvalue:<activityType>"` — value `"<attributesType>|<pushToStartToken>"`.
/// The registrar skips a registration whose stored signature is unchanged; a new token, user, or
/// device yields a new signature and re-registers. The persisted token value lets the registrar
/// re-seed and register a push-to-start token on a launch where ActivityKit does not re-yield it.
///
/// The store is a plain keyed string map; all key-namespacing policy lives in the registrar.
protocol LiveActivityTokenStorage {
    /// The last stored value for `activityType` (a signature or a persisted token), or `nil`.
    func registrationSignature(activityType: String) -> String?
    /// Record `signature` as the last value for `activityType`.
    func setRegistrationSignature(activityType: String, signature: String)
    /// Remove the stored value for a single `activityType` (e.g. when an instance ends).
    func clearRegistrationSignature(activityType: String)
    /// All keys currently held, so the registrar can seed persisted push-to-start tokens at launch
    /// and clear dedup signatures selectively (preserving persisted tokens) on reset.
    func allRegistrationKeys() -> [String]
    /// Remove all stored entries (e.g. full teardown), forcing re-registration.
    func clearAll()
}
