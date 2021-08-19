@testable import Common
import Foundation
@testable import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    func test_givenX_expectY() {
        XCTAssertTrue(SdkVersion.version.matches(regex: #"(\d+)\.(\d+)\.(\d+)(-alpha|-beta)*"#))
    }
}
