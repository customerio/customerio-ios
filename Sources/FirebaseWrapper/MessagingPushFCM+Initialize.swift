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

     The app links FirebaseMessaging itself (any version from 8.7.0); this module finds it at runtime.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()
    ) -> MessagingPushInstance {
        let firebaseService = FirebaseImpl()
        if !firebaseService.isFirebaseMessagingLinked {
            DIGraphShared.shared.logger.error("CIO: FirebaseMessaging isn't linked into the app. Add the FirebaseMessaging product (SwiftPM) or pod to use MessagingPushFCM.")
        }
        return internalSetup(withConfig: config, firebaseService: firebaseService)
    }
}
