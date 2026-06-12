@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class DIGraphTests: BaseDIGraphTest {
    func testDependencyGraphComplete() {
        runTest_expectDiGraphResolvesAllDependenciesWithoutError()
    }
}
