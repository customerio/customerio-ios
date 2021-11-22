import Foundation

public protocol CanSwizzleScreenViews {
    func setupScreenViewTracking()
}

public protocol TrackingInstance: AutoMockable {}

/**
 Tracking features of the Customer.io SDK!

 With this class, you are able to easily perform actions such as tracking events and customers.

 To use this class, you have 2 options:
 1. If you are using the convenient singleton feature of the SDK, you are able to simply
 call the functions of this class: `Tracking.instance.identify()`
 2. Construct a new instance of the `Tracking` class:
 ```
 let customerIO = CustomerIO(...)
 let cioTracking = Tracking(customerIO: customerIO)
 ```
 */
public class Tracking: TrackingInstance {
    /// Singleton shared instance of `Tracking`. Use this if you use the singeton instance of the `CustomerIO` class.
    @Atomic public private(set) static var shared = Tracking(customerIO: CustomerIO.shared)

    private let customerIO: CustomerIO!

    /// testing init
    internal init(customerIO: CustomerIO?) {
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
    }

    /**
     Create a new instance of the `Tracking` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
    }
}
