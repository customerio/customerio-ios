@testable import CIO
import XCTest

class ExampleTest: XCTestCase {
    let example = Example()

    func test_add_givenNumbers_expectAddThem() {
        XCTAssertEqual(example.add(2, 2), 4)
    }

    func test_callNetwork() {
        example.performNetworkCall()
    }
}
