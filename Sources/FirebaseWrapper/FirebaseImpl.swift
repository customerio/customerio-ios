// Moved from customerio/customerio-ios-fcm (Sources/CioFirebaseWrapper.swift, FID branch, #21).
// Compiled only when the package's `FCM` trait is enabled, so APN-only apps never import Firebase.
#if FCM
import CioMessagingPushFCM
import FirebaseInstallations
import FirebaseMessaging

// FID registration APIs, added in FirebaseMessaging 12.16.0.
// Called at runtime so the wrapper still builds with older Firebase versions.
@objc private protocol FIDRegistration {
    var isInstallationIdEnabled: Bool { get }
    func register(completion: @escaping (Error?) -> Void)
}

class FirebaseImpl: FirebaseService {
    private let registrationObserver: FirebaseRegistrationObserver

    init(notificationCenter: NotificationCenter = .default) {
        self.registrationObserver = FirebaseRegistrationObserver(notificationCenter: notificationCenter)
        registrationObserver.isInstallationIdEnabled = { [weak self] in
            self?.isInstallationIdEnabled ?? false
        }
    }

    public var apnsToken: Data? {
        get { Messaging.messaging().apnsToken }
        set { Messaging.messaging().apnsToken = newValue }
    }

    public var delegate: FirebaseServiceDelegate? {
        get { registrationObserver.delegate }
        set { registrationObserver.delegate = newValue }
    }

    public func fetchToken(completion: @escaping (String?, Error?) -> Void) {
        Messaging.messaging().token(completion: completion)
    }

    public var isInstallationIdEnabled: Bool {
        fidRegistration?.isInstallationIdEnabled ?? false
    }

    public func fetchInstallationId(completion: @escaping (String?, Error?) -> Void) {
        guard let fidRegistration = fidRegistration else {
            completion(nil, nil)
            return
        }
        fidRegistration.register { error in
            if let error = error {
                completion(nil, error)
                return
            }
            // The FID Firebase registered with FCM
            Installations.installations().installationID(completion: completion)
        }
    }

    // nil when the app's Firebase version has no FID registration
    private var fidRegistration: FIDRegistration? {
        let messaging = Messaging.messaging()
        guard messaging.responds(to: #selector(FIDRegistration.register(completion:))),
              messaging.responds(to: #selector(getter: FIDRegistration.isInstallationIdEnabled))
        else {
            return nil
        }
        return unsafeBitCast(messaging, to: FIDRegistration.self)
    }
}

// Forwards Firebase's registration updates from its notification instead of taking over `Messaging.delegate`,
// so the app's own MessagingDelegate keeps working. Firebase posts it whenever it calls its delegate (checked 8.7.0 to 12.17.0).
class FirebaseRegistrationObserver: NSObject {
    weak var delegate: FirebaseServiceDelegate?
    var isInstallationIdEnabled: () -> Bool = { false }

    init(notificationCenter: NotificationCenter) {
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(registrationRefreshed(_:)),
            name: .MessagingRegistrationTokenRefreshed,
            object: nil
        )
    }

    // Carries the FID in FID mode, otherwise the token. Same check Firebase uses to pick its delegate method.
    @objc private func registrationRefreshed(_ notification: Notification) {
        let registration = notification.object as? String
        if isInstallationIdEnabled() {
            delegate?.didReceiveRegistration(registration)
        } else {
            delegate?.didReceiveRegistrationToken(registration)
        }
    }
}
#endif
