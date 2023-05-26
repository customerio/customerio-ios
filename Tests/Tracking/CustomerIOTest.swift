import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let hooksMock = HooksManagerMock()
    private let cleanupRepositoryMock = CleanupRepositoryMock()
    private let implmentationMock = CustomerIOInstanceMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    private var customerIO: CustomerIO!

    override func setUp() {
        super.setUp()

        diGraph.override(value: hooksMock, forType: HooksManager.self)
        diGraph.override(value: cleanupRepositoryMock, forType: CleanupRepository.self)
        diGraph.override(value: globalDataStoreMock, forType: GlobalDataStore.self)

        customerIO = CustomerIO(implementation: implmentationMock, diGraph: diGraph)
    }

    func test_initialize_expectAddModuleHooks_expectRunCleanup() {
        customerIO.postInitialize(diGraph: diGraph)

        XCTAssertEqual(hooksMock.addCallsCount, 1)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .tracking)

        XCTAssertEqual(cleanupRepositoryMock.cleanupCallsCount, 1)
    }
}
