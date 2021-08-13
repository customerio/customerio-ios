@testable import CIO
import Foundation
import XCTest

class DateFormatterTest: UnitTest {
    func test_iso8601_expectCreateDateFromFormatter() {
        let formatter = DateFormatter.iso8601
        let givenDateString = "2021-02-14T15:09:02-0600"

        let hardCodedDate = formatter.date(from: givenDateString)!
        let actualString = formatter.string(from: hardCodedDate)

        XCTAssertEqual(givenDateString, actualString)
    }
}
