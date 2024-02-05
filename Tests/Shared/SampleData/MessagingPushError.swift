import Foundation

/// Class to represent generic errors related to push notification operations, specifically for testing MessagingPush API.
public enum MessagingPushError: Error {
    /// Indicates a failure in the registration process for push notifications.
    case registrationFailed
}
