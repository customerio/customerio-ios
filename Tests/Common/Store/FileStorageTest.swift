@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

// MARK: integration tests

#if !os(Linux) // LINUX_DISABLE_FILEMANAGER
class FileStorageTest: UnitTest {
    private var fileStorage: FileManagerFileStorage!
    private var siteId: String!

    override func setUp() {
        siteId = String.random()

        super.setUp(siteId: siteId)

        fileStorage = FileManagerFileStorage(logger: LoggerMock())
    }

    func test_get_givenNotSave_expectNil() {
        XCTAssertNil(fileStorage.get(type: .queueInventory, fileId: nil))
    }

    func test_saveThenGet_expectGetDataSaved() {
        let expected = "hello ami!"

        let didSaveSuccessfully = fileStorage.save(type: .queueInventory, contents: expected.data, fileId: nil)
        XCTAssertTrue(didSaveSuccessfully)

        let actual = fileStorage.get(type: .queueInventory, fileId: nil)

        XCTAssertNotNil(actual)
        XCTAssertEqual(expected, actual!.string!)
    }

    // MARK: getPathToFile

    func test_getPathToFile_expectFileInsideSDKDirectory_expectFileInSubdirectory() {
        let actual = try? fileStorage.getPathToFile(type: .queueInventory, fileId: nil)!

        XCTAssertNotNil(actual)
        // We expect to see "io.customer" as a directory where all SDK files are stored.
        // We then expect to see files inside of their own subdirectories within the SDK root directory.
        XCTAssertMatches(actual?.absoluteString, regex: ".*/io.customer/queue/inventory.json")
    }
}
#endif
