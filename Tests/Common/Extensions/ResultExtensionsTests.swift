@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ResultExtensionsTest: UnitTest {
    // MARK: isSuccess

    func test_givenSuccess_expectIsSuccessTrue() {
        let result: Result<String, Error> = .success("hello")

        XCTAssertTrue(result.isSuccess)
    }

    func test_givenFailure_expectIsSuccessFalse() {
        let result: Result<String, Error> = .failure(HttpRequestError.cancelled)

        XCTAssertFalse(result.isSuccess)
    }
}
