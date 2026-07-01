import Foundation

/// Persists push-to-start registration state for Live Activities.
///
/// One signature is stored per activity type. A signature is `"<pushToStartToken>|<userId>"`;
/// the registrar skips re-registering a type whose stored signature is unchanged, so the same
/// token+user on every launch does not re-send. A new token or a new user yields a new
/// signature and re-registers.
protocol LiveActivityTokenStorage {
    /// The last registered signature for `activityType`, or `nil` if none / not registrable yet.
    func registrationSignature(activityType: String) -> String?
    /// Record `signature` as the last one sent for `activityType`.
    func setRegistrationSignature(activityType: String, signature: String)
    /// Remove all stored signatures (e.g. on reset), forcing re-registration.
    func clearAll()
}
