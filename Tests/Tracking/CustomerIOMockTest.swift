@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

/// Tests using the `CustomerIOInstanceMock` to assert that the mock works as expected
/// for customers and to give examples to them to use.
///
/// Note: In the future we may want to move this code into the Remote Habits app instead.
class CustomerIOMockTest: UnitTest {
    private var cioMock = CustomerIOInstanceMock()
    private var repository: ExampleRepository!

    override func setUp() {
        super.setUp()

        repository = ExampleRepository(cio: cioMock)
    }
}

class ExampleRepository {
    private let cio: CustomerIOInstance

    init(cio: CustomerIOInstance) {
        self.cio = cio
    }

    func loginUser(
        email: String,
        password: String,
        firstName: String,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        // call your code for your app to login the user with email and password.
        // then, identify the customer in Customer.io
        cio.identify(identifier: email, body: ["firstName": firstName])

        onComplete(.success(()))
    }
}

public enum ExampleRepositoryError: Error {
    /// Error that can be tried again to succeed
    case tryLoggingInAgain
}

extension ExampleRepositoryError: CustomStringConvertible, LocalizedError {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .tryLoggingInAgain: return "Sorry, there was a problem logging in. Please, try again."
        }
    }
}
