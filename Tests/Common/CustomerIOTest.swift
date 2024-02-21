@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let implmentationMock = CustomerIOInstanceMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    private var customerIO: CustomerIO!

    override func setUpDependencies() {
        super.setUpDependencies()
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    override func initializeSDKComponents() -> CustomerIO? {
        customerIO = CustomerIO.setUpSharedInstanceForUnitTest(implementation: implmentationMock)
        return customerIO
    }

    func test_initialize_givenPushDeviceTokenNotSet_expectRegisterDeviceTokenNotCalled() {
        customerIO.postInitialize()
        XCTAssertFalse(implmentationMock.registerDeviceTokenCalled)
    }

    func test_initialize_givenPushDeviceTokenSet_expectRegisterDeviceTokenCalled() {
        let pushDeviceToken = String.random
        globalDataStoreMock.pushDeviceToken = pushDeviceToken
        customerIO.postInitialize()
        XCTAssertTrue(implmentationMock.registerDeviceTokenCalled)
    }
}
