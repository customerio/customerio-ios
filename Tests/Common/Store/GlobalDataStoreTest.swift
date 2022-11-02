@testable import Common
import Foundation
import SharedTests
import XCTest

class GlobalDataStoreTest: UnitTest {
    var store: CioGlobalDataStore!

    override func setUp() {
        super.setUp()

        store = CioGlobalDataStore()
    }
}
