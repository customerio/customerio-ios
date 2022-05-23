import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance {}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
 */
public class MessagingInApp: MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp(customerIO: CustomerIO.shared)

    public let customerIO: CustomerIOInstance!
//    internal var implementation: MessagingInAppImplementation?

    /**
     Create a new instance of the `MessagingInApp` class.

     - Parameters:
     - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIOInstance) {
        self.customerIO = customerIO
        // XXX: customers may want to know if siteId nil. Log it to them to help debug.
        if let siteId = customerIO.siteId {
            let diGraphTracking = DICommon.getInstance(siteId: siteId)
            let logger = diGraphTracking.logger

            // make sure we can successfully import Gist SDK.
            Gist.shared.setup(organizationId: "")

            logger.info("MessagingPush module setup with SDK")
            // Register MessagingPush module hooks now that the module is being initialized.
            let hooks = diGraphTracking.hooksManager
//            let moduleHookProvider = MessagingPushModuleHookProvider(siteId: siteId)

//            hooks.add(key: .messagingPush, provider: moduleHookProvider)

//            self.implementation = MessagingPushImplementation(siteId: siteId)
        }
    }
}
