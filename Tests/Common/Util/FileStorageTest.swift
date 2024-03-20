@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class FileTypeTest: UnitTest {
    // MARK: getDirectoryPath

    func test_getDirectoryPath_queueInventory_expectExpectedPath() {
        let given = URL(string: "/siteid")!
        let expected = "/siteid/queue/"

        let actual = FileType.queueInventory.getDirectoryPath(directoryUrl: given)

        XCTAssertEqual(actual.absoluteString, expected)
    }

    func test_getDirectoryPath_queueTask_expectExpectedPath() {
        let given = URL(string: "/siteid")!
        let expected = "/siteid/queue/tasks/"

        let actual = FileType.queueTask.getDirectoryPath(directoryUrl: given)

        XCTAssertEqual(actual.absoluteString, expected)
    }
}

// MARK: integration tests

#if !os(Linux) // LINUX_DISABLE_FILEMANAGER
class FileStorageTest: UnitTest {
    private var fileStorage: FileManagerFileStorage!
    private var siteId: String!

    override func setUp() {
        super.setUp()

        siteId = String.random()

        fileStorage = FileManagerFileStorage(logger: LoggerMock())
    }

    func test_get_givenNotSave_expectNil() {
        XCTAssertNil(fileStorage.get(siteId: siteId, type: .queueInventory, fileId: nil))
    }

    func test_saveThenGet_expectGetDataSaved() {
        let expected = "hello ami!"

        let didSaveSuccessfully = fileStorage.save(siteId: siteId, type: .queueInventory, contents: expected.data, fileId: nil)
        XCTAssertTrue(didSaveSuccessfully)

        let actual = fileStorage.get(siteId: siteId, type: .queueInventory, fileId: nil)

        XCTAssertNotNil(actual)
        XCTAssertEqual(expected, actual!.string!)
    }

    // MARK: getUrl

    func test_getUrl_expectPartitionBySiteId() {
        let actual = try? fileStorage.getUrl(siteId: siteId, type: .queueInventory, fileId: nil)!

        XCTAssertNotNil(actual)
        XCTAssertMatches(actual?.absoluteString, regex: ".*/\(siteId!)/.*")
    }

    func test_getUrl_givenEachFileType_expectGetExpectedPath() {
        let actual = try? fileStorage.getUrl(siteId: siteId, type: .queueInventory, fileId: nil)!

        XCTAssertNotNil(actual)
        XCTAssertMatches(actual?.absoluteString, regex: ".*/\(siteId!)/queue/inventory.json")
    }
}
#endif
