// Moved from customerio/customerio-ios-fcm (Sources/CioFirebaseWrapper.swift), then made Firebase-free: Firebase is found
// at runtime (see `FirebaseRuntime`), so the SDK declares no Firebase dependency and APN-only apps never resolve it.
import CioInternalCommon
import CioMessagingPushFCM
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum FirebaseImplError: Error, Equatable {
    /// The app doesn't link FirebaseMessaging.
    case firebaseMessagingNotLinked
    /// FirebaseMessaging is linked, but methods the SDK calls have different signatures.
    case incompatibleFirebase(unsatisfied: [String])
}

class FirebaseImpl: FirebaseService {
    /// `FIRMessagingRegistrationTokenRefreshedNotification`. Same value from 8.7.0 to 13.0.1; deprecated in 13.
    static let registrationRefreshedNotification = Notification.Name("com.firebase.messaging.notif.fcm-token-refreshed")
    /// `kFIRAppReadyToConfigureSDKNotification`, which FirebaseCore posts when `FirebaseApp.configure()` runs (8.7.0 to 13.0.1).
    static let firebaseAppReadyNotification = Notification.Name("FIRAppReadyToConfigureSDKNotification")
    private static let firebaseAppIsDefaultAppKey = "FIRAppIsDefaultAppKey"

    // A value set before `FirebaseApp.configure()`, applied once Firebase is ready. The latest one wins; nil clears.
    private enum PendingAPNsToken {
        case unchanged
        case replace(Data?)
    }

    // Work that waits for `FirebaseApp.configure()`, taken in one piece so each item runs exactly once.
    private struct PendingWork {
        var apnsToken = PendingAPNsToken.unchanged
        var tokenFetches: [(String?, Error?) -> Void] = []
        var installationIdFetches: [(String?, Error?) -> Void] = []
        var installInterposer = true
    }

    private struct State {
        var pending = PendingWork()
        var hasLoggedWaitingForFirebase = false
        // Firebase calls its delegate, then posts the refresh notification for the same value. Set when the interposer
        // delivers one, so the paired notification isn't forwarded twice; delegate identity can't tell, as delegates chain.
        var registrationDeliveredByDelegate: String??
    }

    private let runtime: FirebaseRuntime
    private let notificationCenter: NotificationCenter
    private let logger: Logger
    private let isInstallationIdEnabledInInfoPlist: () -> Bool
    private let state = Synchronized(State())
    // Serializes applying pending work, so a queued APNs token always reaches Firebase before queued fetches.
    private let flushLock = NSRecursiveLock()
    private var observers: [NSObjectProtocol] = []
    private lazy var interposer = FirebaseMessagingDelegateInterposer { [weak self] registration, isInstallationId in
        self?.registrationReceivedFromDelegate(registration, isInstallationId: isInstallationId)
    }

    weak var delegate: FirebaseServiceDelegate?

    init(
        runtime: FirebaseRuntime = FirebaseRuntime(),
        notificationCenter: NotificationCenter = .default,
        logger: Logger,
        isInstallationIdEnabledInInfoPlist: @escaping () -> Bool = FirebaseImpl.readInstallationIdEnabledFromInfoPlist
    ) {
        self.runtime = runtime
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.isInstallationIdEnabledInInfoPlist = isInstallationIdEnabledInInfoPlist

        // Subscribe before the first probe, so a configuration in between isn't missed.
        observeReadiness()
        observers.append(notificationCenter.addObserver(forName: Self.registrationRefreshedNotification, object: nil, queue: nil) { [weak self] notification in
            self?.registrationRefreshed(notification.object as? String)
        })
        flushIfFirebaseIsReady()
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
    }

    var availability: FirebaseRuntime.Availability {
        runtime.availability
    }

    var apnsToken: Data? {
        get {
            if let messaging = runtime.messaging() {
                return messaging.apnsToken
            }
            return state.using { state in
                if case .replace(let token) = state.pending.apnsToken { return token }
                return nil
            }
        }
        set {
            guard runtime.availability == .available else { return }
            state.mutating { $0.pending.apnsToken = .replace(newValue) }
            flushIfFirebaseIsReady()
            logIfWaitingForFirebase()
        }
    }

    func fetchToken(completion: @escaping (String?, Error?) -> Void) {
        if let error = unavailableError {
            completion(nil, error)
            return
        }
        state.mutating { $0.pending.tokenFetches.append(completion) }
        flushIfFirebaseIsReady()
        logIfWaitingForFirebase()
    }

    var isInstallationIdEnabled: Bool {
        if let messaging = runtime.messaging(), let registration = runtime.installationIdRegistration(of: messaging) {
            return registration.isInstallationIdEnabled
        }
        // Before `FirebaseApp.configure()`: the same rule Firebase applies, FID APIs present and the Info.plist flag on.
        return runtime.supportsInstallationId && isInstallationIdEnabledInInfoPlist()
    }

    func fetchInstallationId(completion: @escaping (String?, Error?) -> Void) {
        guard runtime.supportsInstallationId else {
            completion(nil, nil)
            return
        }
        state.mutating { $0.pending.installationIdFetches.append(completion) }
        flushIfFirebaseIsReady()
        logIfWaitingForFirebase()
    }

    // MARK: - Waiting for FirebaseApp.configure()

    private var unavailableError: FirebaseImplError? {
        switch runtime.availability {
        case .available: return nil
        case .missing: return .firebaseMessagingNotLinked
        case .incompatible(let unsatisfied): return .incompatibleFirebase(unsatisfied: unsatisfied)
        }
    }

    private func observeReadiness() {
        observers.append(notificationCenter.addObserver(forName: Self.firebaseAppReadyNotification, object: nil, queue: nil) { [weak self] notification in
            let isDefaultApp = (notification.userInfo?[Self.firebaseAppIsDefaultAppKey] as? NSNumber)?.boolValue ?? true
            guard isDefaultApp else { return }
            // FirebaseCore posts this while configuring; read Messaging after it returns.
            DispatchQueue.main.async { self?.flushIfFirebaseIsReady() }
        })
        #if canImport(UIKit)
        // Recovery path in case the configure notification is missed or changes.
        observers.append(notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.flushIfFirebaseIsReady()
        })
        #endif
    }

    /// Applies everything queued while Firebase wasn't configured: the APNs token first, then fetches, each exactly once.
    func flushIfFirebaseIsReady() {
        flushLock.lock()
        defer { flushLock.unlock() }

        guard let messaging = runtime.messaging() else { return }
        let work = state.mutating { state -> PendingWork in
            defer { state.pending = PendingWork(installInterposer: false) }
            return state.pending
        }

        if case .replace(let token) = work.apnsToken {
            messaging.apnsToken = token
        }
        if work.installInterposer {
            installDelegateInterposer(on: messaging)
        }
        work.tokenFetches.forEach { messaging.token(completion: $0) }
        work.installationIdFetches.forEach { fetchInstallationId(from: messaging, completion: $0) }
    }

    private func fetchInstallationId(from messaging: RuntimeMessaging, completion: @escaping (String?, Error?) -> Void) {
        guard let registration = runtime.installationIdRegistration(of: messaging), let installations = runtime.installations() else {
            completion(nil, nil)
            return
        }
        registration.register { error in
            if let error = error {
                completion(nil, error)
                return
            }
            // The FID Firebase registered with FCM
            installations.installationID(completion: completion)
        }
    }

    private func logIfWaitingForFirebase() {
        guard runtime.availability == .available, runtime.messaging() == nil else { return }
        let shouldLog = state.mutating { state -> Bool in
            defer { state.hasLoggedWaitingForFirebase = true }
            return !state.hasLoggedWaitingForFirebase
        }
        if shouldLog {
            logger.info("CIO: Firebase isn't configured yet. The device registers with FCM once FirebaseApp.configure() runs.")
        }
    }

    // MARK: - Registration updates

    private func installDelegateInterposer(on messaging: RuntimeMessaging) {
        let current = messaging.delegate
        guard current !== interposer else { return }
        // A non-NSObject delegate can't be forwarded to; leave it, and rely on the notification.
        if let current = current, !(current is NSObject) { return }
        interposer.downstream = current as? NSObject
        messaging.delegate = interposer
    }

    private func registrationReceivedFromDelegate(_ registration: String?, isInstallationId: Bool) {
        state.mutating { $0.registrationDeliveredByDelegate = .some(registration) }
        forwardRegistration(registration, isInstallationId: isInstallationId)
    }

    // Fallback for when another object replaced the interposer as Firebase's delegate.
    private func registrationRefreshed(_ registration: String?) {
        let wasDeliveredByDelegate = state.mutating { state -> Bool in
            guard case .some(let delivered) = state.registrationDeliveredByDelegate, delivered == registration else { return false }
            state.registrationDeliveredByDelegate = .none
            return true
        }
        guard !wasDeliveredByDelegate else { return }
        // Carries the FID in FID mode, otherwise the token. Same check Firebase uses to pick its delegate method.
        forwardRegistration(registration, isInstallationId: isInstallationIdEnabled)
    }

    private func forwardRegistration(_ registration: String?, isInstallationId: Bool) {
        if isInstallationId {
            delegate?.didReceiveRegistration(registration)
        } else {
            delegate?.didReceiveRegistrationToken(registration)
        }
    }

    /// Firebase's own FID-mode setting, read the way FirebaseMessaging reads it.
    static func readInstallationIdEnabledFromInfoPlist() -> Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FirebaseMessagingInstallationIdEnabled")
        return (value as? NSNumber)?.boolValue ?? (value as? NSString)?.boolValue ?? false
    }
}
