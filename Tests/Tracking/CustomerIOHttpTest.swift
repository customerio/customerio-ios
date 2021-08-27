@testable import CioTracking
import Foundation
import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/**
 Test that performs a real HTTP request to Customer.io API.

 These tests are meant to run on your local machine, not CI server.
 */
class TrackingHttpTest: HttpTest {
    func test_identify_expectIdentifyProfileInWorkspace() throws {
        guard let customerIO = customerIO else { return try XCTSkipIf(true) }

        let givenIdentifier = String(Int.random(in: 1000 ..< 9999))
        let givenEmail = EmailAddress.randomEmail

        print("Identifing profile: \(givenIdentifier), \(givenEmail)")

        let expect = expectation(description: "Expect to finsh call")
        customerIO.identify(identifier: givenIdentifier, onComplete: { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)

            case .success:
                print("Success!! Check your workspace to see if you see the new profile")
            }

            expect.fulfill()
        }, email: givenEmail)

        waitForExpectations()
    }
}
