@testable import CIO
import XCTest

class ExampleTest: XCTestCase {
    var exampleViewModelMock: ExampleViewModelMock!
    var example: Example!

    override func setUp() {
        exampleViewModelMock = ExampleViewModelMock()
        DI.shared.override(.exampleViewModel, value: exampleViewModelMock, forType: ExampleViewModel.self)

        example = Example()
    }

    func test_performNetworkCall_expectNetworkCallToComplete() {
        exampleViewModelMock.callNetworkClosure = { onComplete in onComplete() }

        XCTAssertEqual(example.numberTimesNetworkCalled, 0)

        example.performNetworkCall()

        XCTAssertEqual(example.numberTimesNetworkCalled, 1)
    }
}
