import Foundation
import ObjectiveC

// FirebaseMessaging's Objective-C API (FIRMessaging.h), the part the adapter calls.
@objc protocol RuntimeMessaging {
    @objc(APNSToken) var apnsToken: Data? { get set }
    @objc var delegate: AnyObject? { get set }
    @objc(tokenWithCompletion:) func token(completion: @escaping (String?, Error?) -> Void)
}

// FID registration APIs, added in FirebaseMessaging 12.16.0.
@objc protocol RuntimeInstallationIdRegistration {
    var isInstallationIdEnabled: Bool { get }
    @objc(registerWithCompletion:) func register(completion: @escaping (Error?) -> Void)
}

// FirebaseInstallations' Objective-C API (FIRInstallations.h).
@objc protocol RuntimeInstallations {
    @objc(installationIDWithCompletion:) func installationID(completion: @escaping (String?, Error?) -> Void)
}

/// Finds FirebaseMessaging and FirebaseInstallations in the app at runtime, so the SDK declares no Firebase dependency.
///
/// Objects are only handed out after the class, and the object's actual class, satisfy every `ObjCMethodContract` the
/// adapter relies on. Names and types are unchanged from FirebaseMessaging 8.7.0 to 13.0.1.
final class FirebaseRuntime {
    enum Availability: Equatable {
        /// FirebaseMessaging isn't linked into the app.
        case missing
        /// FirebaseMessaging is linked, but methods the adapter calls have different signatures.
        case incompatible(unsatisfied: [String])
        case available
    }

    static let messagingContracts = [
        ObjCMethodContract(NSSelectorFromString("messaging"), .class, returns: .object),
        ObjCMethodContract(NSSelectorFromString("APNSToken"), returns: .object),
        ObjCMethodContract(NSSelectorFromString("setAPNSToken:"), returns: .void, arguments: [.object]),
        ObjCMethodContract(NSSelectorFromString("delegate"), returns: .object),
        ObjCMethodContract(NSSelectorFromString("setDelegate:"), returns: .void, arguments: [.object]),
        ObjCMethodContract(NSSelectorFromString("tokenWithCompletion:"), returns: .void, arguments: [.block])
    ]

    static let installationIdRegistrationContracts = [
        ObjCMethodContract(NSSelectorFromString("isInstallationIdEnabled"), returns: .bool),
        ObjCMethodContract(NSSelectorFromString("registerWithCompletion:"), returns: .void, arguments: [.block])
    ]

    static let installationsContracts = [
        ObjCMethodContract(NSSelectorFromString("installations"), .class, returns: .object),
        ObjCMethodContract(NSSelectorFromString("installationIDWithCompletion:"), returns: .void, arguments: [.block])
    ]

    private let messagingClassName: String
    private let installationsClassName: String

    init(messagingClassName: String = "FIRMessaging", installationsClassName: String = "FIRInstallations") {
        self.messagingClassName = messagingClassName
        self.installationsClassName = installationsClassName
    }

    var availability: Availability {
        guard let messagingClass = NSClassFromString(messagingClassName) else { return .missing }
        let unsatisfied = Self.messagingContracts.unsatisfied(by: messagingClass)
        guard unsatisfied.isEmpty else {
            return .incompatible(unsatisfied: unsatisfied.map { NSStringFromSelector($0.selector) })
        }
        return .available
    }

    /// Whether the linked Firebase can register through the Firebase Installation ID (FID). Answerable before
    /// `FirebaseApp.configure()`, because it only looks at classes.
    var supportsInstallationId: Bool {
        guard availability == .available,
              let messagingClass = NSClassFromString(messagingClassName),
              let installationsClass = NSClassFromString(installationsClassName)
        else {
            return false
        }
        return Self.installationIdRegistrationContracts.unsatisfied(by: messagingClass).isEmpty &&
            Self.installationsContracts.unsatisfied(by: installationsClass).isEmpty
    }

    /// `+[FIRMessaging messaging]`, or nil when FirebaseMessaging is missing, incompatible, or the app hasn't called
    /// `FirebaseApp.configure()` yet.
    func messaging() -> RuntimeMessaging? {
        guard availability == .available,
              let messaging = sharedInstance(className: messagingClassName, selector: "messaging"),
              Self.messagingContracts.filter({ $0.kind == .instance }).unsatisfied(by: type(of: messaging)).isEmpty
        else {
            return nil
        }
        return unsafeBitCast(messaging, to: RuntimeMessaging.self)
    }

    /// The FID registration API of `messaging`, or nil when the app's Firebase version has none.
    func installationIdRegistration(of messaging: RuntimeMessaging) -> RuntimeInstallationIdRegistration? {
        guard let object = messaging as? NSObject,
              Self.installationIdRegistrationContracts.unsatisfied(by: type(of: object)).isEmpty
        else {
            return nil
        }
        return unsafeBitCast(object, to: RuntimeInstallationIdRegistration.self)
    }

    /// `+[FIRInstallations installations]`, or nil when it's missing, incompatible or not configured.
    func installations() -> RuntimeInstallations? {
        guard let installationsClass = NSClassFromString(installationsClassName),
              Self.installationsContracts.unsatisfied(by: installationsClass).isEmpty,
              let installations = sharedInstance(className: installationsClassName, selector: "installations"),
              Self.installationsContracts.filter({ $0.kind == .instance }).unsatisfied(by: type(of: installations)).isEmpty
        else {
            return nil
        }
        return unsafeBitCast(installations, to: RuntimeInstallations.self)
    }

    // The object a class method such as `+[FIRMessaging messaging]` returns, checked to be an instance of that class.
    // Both class methods are validated as returning an object before this is called.
    private func sharedInstance(className: String, selector: String) -> NSObject? {
        guard let objectClass = NSClassFromString(className) as? NSObject.Type else { return nil }
        let instance = objectClass.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? NSObject
        guard let instance = instance, instance.isKind(of: objectClass) else { return nil }
        return instance
    }
}
