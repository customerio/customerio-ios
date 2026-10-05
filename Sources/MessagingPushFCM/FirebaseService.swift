import Foundation

/// A protocol to abstract Firebase functionality without Firebase dependencies
public protocol FirebaseService: AnyObject {
    /// The current APNS token set on the Firebase service
    var apnsToken: Data? { get set }

    /// Fetch the current FCM registration token
    /// - Parameter completion: Called with the token or error
    func fetchToken(completion: @escaping (String?, Error?) -> Void)

    /// Whether the app registers with FCM through its Firebase Installation ID (FID mode).
    /// `false` when the app's Firebase version doesn't support FID registration.
    var isInstallationIdEnabled: Bool { get }

    /// Register the app with FCM through its Firebase Installation ID (FID), then fetch the FID.
    /// Only used when `isInstallationIdEnabled` is `true`.
    /// - Parameter completion: Called with the FID or error
    func fetchInstallationId(completion: @escaping (String?, Error?) -> Void)

    /// The delegate for receiving Firebase events
    var delegate: FirebaseServiceDelegate? { get set }
}

// Defaults keep services written before FID support working in token mode.
public extension FirebaseService {
    var isInstallationIdEnabled: Bool { false }

    func fetchInstallationId(completion: @escaping (String?, Error?) -> Void) {
        completion(nil, nil)
    }
}

/// A protocol to handle Firebase events without Firebase dependencies
public protocol FirebaseServiceDelegate: AnyObject {
    /// Called when a new FCM registration token is available
    /// - Parameter token: The new registration token as a string
    func didReceiveRegistrationToken(_ token: String?)

    /// Called when the app is registered with FCM through its Firebase Installation ID (FID mode)
    /// - Parameter installationId: The registered Firebase Installation ID
    func didReceiveRegistration(_ installationId: String?)

    /// Called when the app's Firebase Installation ID is unregistered from FCM (FID mode)
    /// - Parameter installationId: The unregistered Firebase Installation ID
    func didUnregister(_ installationId: String)
}

// Defaults keep delegates written before FID support compiling.
public extension FirebaseServiceDelegate {
    func didReceiveRegistration(_ installationId: String?) {}

    func didUnregister(_ installationId: String) {}
}
