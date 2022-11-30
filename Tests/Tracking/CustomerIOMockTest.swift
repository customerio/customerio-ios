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

    func test_identify_requestBody_exampleTestCheckingArguments() {
        let givenEmail = "example@customer.io"
        let givenFirstName = "Dana"
        let givenBody = ExampleIdentifyRequestBody(firstName: givenFirstName)

        // Call your code under test
        let expect = expectation(description: "Expect login to complete")
        repository.loginUser(email: givenEmail, password: "password", firstName: givenFirstName) { _ in
            expect.fulfill()
        }

        // wait for your function under test to complete
        waitForExpectations(0.3)

        // You can now check the Customer.io mock to see if it behaved as you wished.
        XCTAssertTrue(cioMock.identifyCalled)

        // You can receive the generic `body` that was sent to the Customer.io `identify()` call.
        // Because of Swift generics, you must get the `.value` and cast it:
        let actualBody: ExampleIdentifyRequestBody? = cioMock.identifyEncodableReceivedArguments?.body
            .value as? ExampleIdentifyRequestBody
        // Now, you can run checks against the `body` that was actually passed to `identify()`.
        XCTAssertNotNil(actualBody)
        XCTAssertEqual(actualBody?.firstName, givenBody.firstName)
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
        cio.identify(identifier: email, body: ExampleIdentifyRequestBody(firstName: firstName))

        onComplete(.success(()))
    }
}

struct ExampleIdentifyRequestBody: Encodable {
    // Include properties below for attributes you would like to associate with the customer.
    // Here, we are going to track the `first_name` of the customer.
    let firstName: String
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
