import CioTracking
import Foundation

public protocol MessagingPushInstance: AutoMockable {
    func registerDeviceToken(_ deviceToken: String, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
    func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )
}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */

public class MessagingPush: MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush(customerIO: CustomerIO.shared)

    public let customerIO: CustomerIOInstance!
    internal var implementation: MessagingPushImplementation?

    /**
     Create a new instance of the `MessagingPush` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIOInstance) {
        self.customerIO = customerIO
        // XXX: customers may want to know if siteId nil. Log it to them to help debug.
        if let siteId = customerIO.siteId {
            self.implementation = MessagingPushImplementation(siteId: siteId)
        }
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String,
                                    onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.registerDeviceToken(deviceToken, onComplete: onComplete)
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.deleteDeviceToken(onComplete: onComplete)
    }

    /**
        Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken,
                                   onComplete: onComplete)
    }
}

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
