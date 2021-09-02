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
    func test_identify_expectIdentifyProfileUsingOnlyId() throws {
        guard let customerIO = customerIO else { return try XCTSkipIf(true) }

        let givenIdentifier = EmailAddress.randomEmail

        print("Identifing profile: \(givenIdentifier)")

        let expect = expectation(description: "Expect to finish call")
        customerIO.identify(identifier: givenIdentifier) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)

            case .success:
                print("Success!! Check your workspace to see if you see the new profile")
            }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_expectIdentifyProfileInWorkspace() throws {
        guard let customerIO = customerIO else { return try XCTSkipIf(true) }

        let givenIdentifier = String(Int.random(in: 1000 ..< 9999))
        let givenEmail = EmailAddress.randomEmail
        let givenBody = IdentifyRequestBody.random(update: false)

        print("Identifing profile: \(givenIdentifier), \(givenEmail)")

        let expect = expectation(description: "Expect to finish call")
        customerIO.identify(identifier: givenIdentifier, body: givenBody) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)

            case .success:
                print("Success!! Check your workspace to see if you see the new profile")
            }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_givenIdOfExistingProfile_expectUpdateProfile() throws {
        guard let customerIO = customerIO else { return try XCTSkipIf(true) }

        let givenIdentifierExistingProfile = "9339"
        let givenUpdateBody = IdentifyRequestBody.random(update: true)

        print("Updating profile: \(givenIdentifierExistingProfile), \(givenUpdateBody)")

        let expect = expectation(description: "Expect to finish call")
        customerIO.identify(identifier: givenIdentifierExistingProfile, body: givenUpdateBody) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)

            case .success:
                print("Success!! Check your workspace to see if you see the new profile")
            }

            expect.fulfill()
        }

        waitForExpectations()
    }
}
