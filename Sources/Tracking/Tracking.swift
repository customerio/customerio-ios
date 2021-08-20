import Common
import Foundation

public class Tracking {
    public private(set) static var instance = Tracking(customerIO: CustomerIO.instance)

    private let customerIO: CustomerIO!

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

        guard let credentials = customerIO.credentials else { return nil }

        _identifyRepository = CIOIdentifyRepository(credentials: credentials, config: customerIO.sdkConfig)

        return _identifyRepository
    }

    private let keyValueStorage: KeyValueStorage

    /// testing init
    internal init(identifyRepository: IdentifyRepository, keyValueStorage: KeyValueStorage) {
        self._identifyRepository = identifyRepository
        self.keyValueStorage = keyValueStorage
        self.customerIO = CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
    }

    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
        self.keyValueStorage = DI
    }

    public func identify(
        id: String,
        onComplete: @escaping (Result<Void, Error>) -> Void,
        email: String? = nil,
        createdAt: Date = Date()
    ) {
        guard let identifyRepository = self.identifyRepository else {
            return onComplete(Result.failure(SdkError.notInitialized))
        }

        identifyRepository.addOrUpdateCustomer(identifier: id, email: email, createdAt: createdAt) { result in
            switch result {
            case .success:
                // save the information to key/value storage

                break
            case .failure(let error):
                return onComplete(Result.failure(error))
            }
        }
    }
}
