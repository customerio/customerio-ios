import Common
import Foundation

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
public class Tracking {
    /// Singleton shared instance of `Tracking`. Use this if you use the singeton instance of the `CustomerIO` class.
    public private(set) static var instance = Tracking(customerIO: CustomerIO.instance)

    private let customerIO: CustomerIO!

    private var credentials: SdkCredentials? {
        customerIO.credentials
    }

    private var sdkConfig: SdkConfig {
        customerIO.sdkConfig
    }

    /**
     allow `_` character in property name. It's common to use a `_` in property name for private variables
     but a refactor in the future will remove the need for this property all together so, just disable
     the lint rule for now.
     */
    // swiftlint:disable identifier_name

    /**
     Keep a class wide reference to `IdentifyRepository` to keep it in memory as it performs async operations.
     */
    private var _identifyRepository: IdentifyRepository?
    /**
     Because the repository can be populated from tests and it depends on the SDK being initialized,
     there needs to exist logic to provide the `IdentifyRepository` instance to the class.

     If a backgroud queue would exist in the SDK, this code can go away where each function of the class
     simply adds a task to the queue and the queue will run or not run the operation depending on if
     the SDK has been initialized.
     */
    private var identifyRepository: IdentifyRepository? {
        if let _identifyRepository = self._identifyRepository { return _identifyRepository }

        guard let credentials = credentials else { return nil }

        _identifyRepository = CIOIdentifyRepository(credentials: credentials, config: sdkConfig)

        return _identifyRepository
    }

    // swiftlint:enable identifier_name

    private let keyValueStorage: KeyValueStorage

    /// testing init
    internal init(customerIO: CustomerIO?, identifyRepository: IdentifyRepository?, keyValueStorage: KeyValueStorage) {
        self._identifyRepository = identifyRepository
        self.keyValueStorage = keyValueStorage
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
    }

    /**
     Create a new instance of the `Tracking` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
        self.keyValueStorage = DICommon.shared.keyValueStorage
    }

    /**
     Identify a customer (aka: Add or update a profile).

     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io

     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.

     - Parameters:
       - identifier: ID you want to assign to the customer.
         This value can be an internal ID that your system uses or an email address.
         [Learn more](https://customer.io/docs/api/#operation/identify)
       - onComplete: Asynchronous callback with `Result` of identifying a customer.
         Check result to see if error or success.
       - email: Optional email address you want to associate with a profile.
         If you use an email address as the `identifier` this is not needed.
     */
    public func identify(
        identifier: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        email: String? = nil
    ) {
        guard let identifyRepository = self.identifyRepository else {
            return onComplete(Result.failure(.notInitialized))
        }

        identifyRepository.addOrUpdateCustomer(identifier: identifier, email: email) { [weak self] result in
            guard self != nil else { return }

            switch result {
            case .success:
                return onComplete(Result.success(()))
            case .failure(let error):
                return onComplete(Result.failure(error))
            }
        }
    }

    /**
     Stop identifying the currently persisted customer. All future calls to the SDK will no longer
     be associated with the previously identified customer.

     Note: If you simply want to identify a *new* customer, this function call is optional. Simply
     call `identify()` again to identify the new customer profile over the existing.

     If no profile has been identified yet, this function will ignore your request.
     */
    public func identifyStop() {
        guard let identifyRepository = self.identifyRepository else {
            return
        }

        identifyRepository.removeCustomer()
    }
}

/**
 The automatically generated dependency injection graph project
 complains when there isn't at least 1 `case` in the enum.

 This solves that problem by placing a placeholder into the graph until we have a class that makes sense.
 */
// sourcery: InjectRegister = "Placeholder"
internal class Placeholder {}
