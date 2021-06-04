@testable import CIO
import XCTest

class ExampleViewModelTest: XCTestCase {
    var viewModel: ExampleViewModel!
    var exampleRepositoryMock: ExampleRepositoryMock!

    override func setUp() {
        exampleRepositoryMock = ExampleRepositoryMock()
        viewModel = AppExampleViewModel(exampleRepository: exampleRepositoryMock)
    }

    func test_callNetwork_assertRepositoryCalled() {
        exampleRepositoryMock.callNetworkClosure = { onComplete in
            onComplete()
        }

        viewModel.callNetwork {
            XCTAssertEqual(self.exampleRepositoryMock.callNetworkCallsCount, 1)
        }
    }

    func test_callNetwork_givenNetworkCallComplete_expectOnCompleteCalled() {
        exampleRepositoryMock.callNetworkClosure = { onComplete in
            onComplete()
        }

        var onCompleteCalled = false
        viewModel.callNetwork {
            onCompleteCalled = true
        }

        XCTAssertTrue(onCompleteCalled)
    }
}
