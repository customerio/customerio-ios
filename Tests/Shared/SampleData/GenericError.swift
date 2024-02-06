import Foundation

/// Class to represent generic errors for testing.
public enum GenericError: Error {
    /// Indicates a failure in the registration process for push notifications, useful for testing MessagingPush API.
    case registrationFailed
}
