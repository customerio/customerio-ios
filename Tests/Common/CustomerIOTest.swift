@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let implmentationMock = CustomerIOInstanceMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    private var customerIO: CustomerIO!

    override func setUp() {
        super.setUp()

        diGraph.override(value: globalDataStoreMock, forType: GlobalDataStore.self)

        customerIO = CustomerIO.setUpSharedInstanceForUnitTest(implementation: implmentationMock, diGraph: diGraph)
    }

    func test_initialize_givenPushDeviceTokenNotSet_expectRegisterDeviceTokenNotCalled() {
        customerIO.postInitialize(diGraph: diGraph)
        XCTAssertFalse(implmentationMock.registerDeviceTokenCalled)
    }

    func test_initialize_givenPushDeviceTokenSet_expectRegisterDeviceTokenCalled() {
        let pushDeviceToken = String.random
        globalDataStoreMock.pushDeviceToken = pushDeviceToken
        customerIO.postInitialize(diGraph: diGraph)
        XCTAssertTrue(implmentationMock.registerDeviceTokenCalled)
    }
}
