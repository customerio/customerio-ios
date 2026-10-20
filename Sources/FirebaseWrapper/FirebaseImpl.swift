// Moved from customerio/customerio-ios-fcm (Sources/CioFirebaseWrapper.swift, FID branch, #21), then made Firebase-free:
// FirebaseMessaging and FirebaseInstallations are Objective-C, so their classes and selectors are looked up at runtime
// in whatever Firebase the app links (SwiftPM, CocoaPods or xcframeworks). customerio-ios declares no Firebase dependency,
// so APN-only apps never resolve it and FCM apps pick any Firebase version. Names checked against 8.7.0 and 13.0.1.
import CioMessagingPushFCM
import Foundation

// FirebaseMessaging's Objective-C API (FIRMessaging.h).
@objc private protocol RuntimeMessaging {
    @objc(APNSToken) var apnsToken: Data? { get set }
    @objc(tokenWithCompletion:) func token(completion: @escaping (String?, Error?) -> Void)
}

// FID registration APIs, added in FirebaseMessaging 12.16.0.
@objc private protocol FIDRegistration {
    var isInstallationIdEnabled: Bool { get }
    func register(completion: @escaping (Error?) -> Void)
}

// FirebaseInstallations' Objective-C API (FIRInstallations.h).
@objc private protocol RuntimeInstallations {
    @objc(installationIDWithCompletion:) func installationID(completion: @escaping (String?, Error?) -> Void)
}

enum FirebaseImplError: Error {
    /// The app doesn't link FirebaseMessaging.
    case firebaseMessagingNotLinked
}

class FirebaseImpl: FirebaseService {
    /// `FIRMessagingRegistrationTokenRefreshedNotification`. Same value from 8.7.0 to 13.0.1.
    static let registrationRefreshedNotification = Notification.Name("com.firebase.messaging.notif.fcm-token-refreshed")

    private let messagingClassName: String
    private let installationsClassName: String
    private let registrationObserver: FirebaseRegistrationObserver

    init(
        notificationCenter: NotificationCenter = .default,
        messagingClassName: String = "FIRMessaging",
        installationsClassName: String = "FIRInstallations"
    ) {
        self.messagingClassName = messagingClassName
        self.installationsClassName = installationsClassName
        self.registrationObserver = FirebaseRegistrationObserver(notificationCenter: notificationCenter)
        registrationObserver.isInstallationIdEnabled = { [weak self] in
            self?.isInstallationIdEnabled ?? false
        }
    }

    var isFirebaseMessagingLinked: Bool {
        messaging != nil
    }

    var apnsToken: Data? {
        get { messaging?.apnsToken }
        set { messaging?.apnsToken = newValue }
    }

    var delegate: FirebaseServiceDelegate? {
        get { registrationObserver.delegate }
        set { registrationObserver.delegate = newValue }
    }

    func fetchToken(completion: @escaping (String?, Error?) -> Void) {
        guard let messaging = messaging else {
            completion(nil, FirebaseImplError.firebaseMessagingNotLinked)
            return
        }
        messaging.token(completion: completion)
    }

    var isInstallationIdEnabled: Bool {
        fidRegistration?.isInstallationIdEnabled ?? false
    }

    func fetchInstallationId(completion: @escaping (String?, Error?) -> Void) {
        guard let fidRegistration = fidRegistration, let installations = installations else {
            completion(nil, nil)
            return
        }
        fidRegistration.register { error in
            if let error = error {
                completion(nil, error)
                return
            }
            // The FID Firebase registered with FCM
            installations.installationID(completion: completion)
        }
    }

    // The object a class method such as `+[FIRMessaging messaging]` returns, or nil when the class isn't linked.
    private func sharedInstance(className: String, selector: String) -> NSObject? {
        guard let objectClass = NSClassFromString(className) as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString(selector)
        guard objectClass.responds(to: selector) else { return nil }
        return objectClass.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    // nil when the app doesn't link FirebaseMessaging
    private var messaging: RuntimeMessaging? {
        guard let messaging = sharedInstance(className: messagingClassName, selector: "messaging"),
              messaging.responds(to: #selector(RuntimeMessaging.token(completion:))),
              messaging.responds(to: #selector(getter: RuntimeMessaging.apnsToken)),
              messaging.responds(to: #selector(setter: RuntimeMessaging.apnsToken))
        else {
            return nil
        }
        return unsafeBitCast(messaging, to: RuntimeMessaging.self)
    }

    // nil when the app's Firebase version has no FID registration
    private var fidRegistration: FIDRegistration? {
        guard let messaging = sharedInstance(className: messagingClassName, selector: "messaging"),
              messaging.responds(to: #selector(FIDRegistration.register(completion:))),
              messaging.responds(to: #selector(getter: FIDRegistration.isInstallationIdEnabled))
        else {
            return nil
        }
        return unsafeBitCast(messaging, to: FIDRegistration.self)
    }

    private var installations: RuntimeInstallations? {
        guard let installations = sharedInstance(className: installationsClassName, selector: "installations"),
              installations.responds(to: #selector(RuntimeInstallations.installationID(completion:)))
        else {
            return nil
        }
        return unsafeBitCast(installations, to: RuntimeInstallations.self)
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
            name: FirebaseImpl.registrationRefreshedNotification,
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
