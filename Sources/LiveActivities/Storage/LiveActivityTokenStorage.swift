import Foundation

/// Persists push-to-start token state for Live Activities.
///
/// One token is stored per activity type. The module uses this to skip re-registering
/// a token that has already been sent to the backend.
protocol LiveActivityTokenStorage {
    func getPushToStartToken(activityType: String) -> String?
    func setPushToStartToken(activityType: String, tokenHex: String)
    func clearAll()
}
