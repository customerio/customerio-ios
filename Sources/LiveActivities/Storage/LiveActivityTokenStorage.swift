import Foundation

/// Persists Live Activity token-registration state so unchanged tokens are not re-sent across
/// app launches.
///
/// Two kinds of signature share this store, distinguished by their key:
/// - push-to-start, keyed by activity type — value `"<deviceToken>|<pushToStartToken>|<userId>"`.
/// - per-instance, keyed by `"instance:<instanceUUID>"` — value `"<deviceToken>|<instanceToken>"`.
/// The registrar skips a registration whose stored signature is unchanged; a new token, user, or
/// device yields a new signature and re-registers.
protocol LiveActivityTokenStorage {
    /// The last registered signature for `activityType`, or `nil` if none / not registrable yet.
    func registrationSignature(activityType: String) -> String?
    /// Record `signature` as the last one sent for `activityType`.
    func setRegistrationSignature(activityType: String, signature: String)
    /// Remove the stored signature for a single `activityType` (e.g. when an instance ends).
    func clearRegistrationSignature(activityType: String)
    /// Remove all stored signatures (e.g. on reset), forcing re-registration.
    func clearAll()
}
