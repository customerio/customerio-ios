import Foundation

/// A protocol to abstract Firebase functionality without Firebase dependencies
public protocol FirebaseService {
    /// The current APNS token set on the Firebase service
    var apnsToken: Data? { get set }

    /// Fetch the current FCM registration token
    /// - Parameter completion: Called with the token or error
    func fetchToken(completion: @escaping (String?, Error?) -> Void)

    /// The delegate for receiving Firebase events
    var delegate: FirebaseServiceDelegate? { get set }
}

/// A protocol to handle Firebase events without Firebase dependencies
public protocol FirebaseServiceDelegate: AnyObject {
    /// Called when a new FCM registration token is available
    /// - Parameter token: The new registration token as a string
    func didReceiveRegistrationToken(_ token: String?)
}
