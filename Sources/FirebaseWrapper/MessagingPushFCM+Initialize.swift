// Moved from customerio/customerio-ios-fcm (Sources/MessagingPushFCM+Init.swift).
// This is the only `initialize(withConfig:)` for MessagingPushFCM. A final customerio-ios-fcm release must not declare
// its own, or apps importing both modules get an ambiguous call.
import CioMessagingPush
import CioMessagingPushFCM

import Foundation

#if FCM
public extension MessagingPushFCM {
    /**
     Initialize and configure `MessagingPushFCM`.
     Call this function in your app if you want to initialize and configure the module to
     auto-fetch device token and auto-register device with Customer.io.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()
    ) -> MessagingPushInstance {
        internalSetup(withConfig: config, firebaseService: FirebaseImpl())
    }
}
#else
public extension MessagingPushFCM {
    /// Without the `FCM` trait this module has no Firebase adapter. The declaration exists only to turn a confusing
    /// "no member 'initialize'" error into instructions.
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    @available(*, unavailable, message: "Enable the FCM trait of the customerio-ios package (Xcode: Package Dependencies > Traits; Package.swift: traits: [\"FCM\"]).")
    static func initialize(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()
    ) -> MessagingPushInstance {
        fatalError("unavailable")
    }
}
#endif
