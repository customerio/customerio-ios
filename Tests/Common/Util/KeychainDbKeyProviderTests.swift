@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import XCTest

class KeychainDbKeyProviderTests: XCTestCase {
    private var graph: DIGraphShared!
    // Unique API key per test avoids leftover database files from affecting each other.
    private var cdpApiKey: String!

    override func setUp() {
        super.setUp()
        graph = DIGraphShared()
        cdpApiKey = "test-\(UUID().uuidString)"
    }

    override func tearDown() {
        graph.reset()
        super.tearDown()
    }

    func test_registerStorageManager_opensDbWithKeyFromProvider() {
        let stub = DbKeyProviderMock()
        stub.getOrCreateDbKeyReturnValue = "deadbeef"
        graph.override(value: stub, forType: DbKeyProvider.self)

        let result = graph.registerStorageManager(cdpApiKey: cdpApiKey)

        XCTAssertNotNil(result, "StorageManager should be created when the key provider succeeds")
        XCTAssertEqual(stub.getOrCreateDbKeyCallsCount, 1)
        XCTAssertEqual(stub.getOrCreateDbKeyReceivedArguments, cdpApiKey)
    }

    func test_registerStorageManager_returnsNilWhenKeyProviderThrows() {
        let stub = DbKeyProviderMock()
        stub.getOrCreateDbKeyThrowableError = KeychainDbKeyError.writeFailed(status: -1)
        graph.override(value: stub, forType: DbKeyProvider.self)

        let result = graph.registerStorageManager(cdpApiKey: cdpApiKey)

        XCTAssertNil(result, "StorageManager should be nil when the key provider throws")
    }
}
