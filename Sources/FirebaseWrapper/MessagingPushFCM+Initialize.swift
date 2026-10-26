// Moved from customerio/customerio-ios-fcm (Sources/MessagingPushFCM+Init.swift).
// This is the only `initialize(withConfig:)` for MessagingPushFCM. A final customerio-ios-fcm release must not declare
// its own, or apps importing both modules get an ambiguous call.
import CioInternalCommon
import CioMessagingPush
import CioMessagingPushFCM

import Foundation

public extension MessagingPushFCM {
    /**
     Initialize and configure `MessagingPushFCM`.
     Call this function in your app if you want to initialize and configure the module to
     auto-fetch device token and auto-register device with Customer.io.

     The app supplies FirebaseMessaging (8.7.0 or later) itself: the SDK declares no Firebase dependency and finds it at
     runtime. Calling this without FirebaseMessaging linked into the app stops the app with a precondition failure.
     Calling it before `FirebaseApp.configure()` is fine; registration waits until Firebase is configured.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()
    ) -> MessagingPushInstance {
        let logger = DIGraphShared.shared.logger
        // Reused across calls, so queued registration work and the delegate chain survive re-initialization.
        let firebaseService = FirebaseImplStore.adapter { FirebaseImpl(logger: logger) }

        switch firebaseService.availability {
        case .available:
            break
        case .missing:
            preconditionFailure(FirebaseWrapperMessages.firebaseMessagingMissing)
        case .incompatible(let unsatisfied):
            // A Firebase version the SDK doesn't support. Registration fails with an error instead of calling methods
            // with the wrong types; debug builds stop here so it's caught before release.
            let message = FirebaseWrapperMessages.incompatibleFirebase(unsatisfied: unsatisfied)
            logger.error(message)
            assertionFailure(message)
        }

        return internalSetup(withConfig: config, firebaseService: firebaseService)
    }
}

enum FirebaseWrapperMessages {
    static let firebaseMessagingMissing = """
    CIO: MessagingPushFCM needs FirebaseMessaging, but it isn't linked into the app. Add the FirebaseMessaging \
    product of firebase-ios-sdk (SwiftPM) or the FirebaseMessaging pod. If Firebase is linked statically, \
    make sure the app links with -ObjC. Apps that don't use FCM should use MessagingPushAPN instead.
    """

    static func incompatibleFirebase(unsatisfied: [String]) -> String {
        "CIO: The app's FirebaseMessaging version isn't supported by MessagingPushFCM: these methods have unexpected signatures: \(unsatisfied.joined(separator: ", "))."
    }
}
