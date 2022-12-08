import Common
import Foundation
import XCTest

// Class that interacts with static files stored in SampleDataFiles resources directory.
//
// Instead of storing long Swift Strings full of data, we store static files in a directory in the Tests/ directory.
// Then, we can read in those files as Strings and use them in test functions.
//
// One common use case of using these static files is to save the file into the FileSystem of the app running during the
// test.
// That means that at runtime in tests, when `FileManager` in the SDK runs, it can read files just like it's running an
// an iOS app.
public class SampleDataFilesUtil {
    private let fileStore: FileStorage

    public init(fileStore: FileStorage) {
        self.fileStore = fileStore
    }

    private let sampleDataFilesRootDirectoryName = "SampleDataFiles"

    public func saveSdkV1QueueFiles() {
        let queueSnapshotFilesDirectoryName = "V1QueueSnapshot"

        saveFileAssertSuccess(
            type: .queueInventory,
            fileName: "inventory.json",
            subdirectory: queueSnapshotFilesDirectoryName
        )

        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "FD677E99-B774-4B12-A30A-B2315D497D36.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "DD1F8FE7-ADDB-4015-849F-4BBD0E537A2C.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "D687EAA8-396F-4DEE-B983-B8CFF723A1B2.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "BDE6D050-3A26-4A4D-B923-B1C52901090E.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "AA6418AC-40D0-4580-93B9-C6262257BAA3.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "A4E62708-F263-4562-8503-CB55B4AE8E39.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "3143DAD0-E28A-42E6-84B1-D9F6779DCF91.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "940DDFFB-BDC6-4452-8895-A43906E75FC2.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "8C686475-FDD4-44BE-B423-B974D4EDF83A.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "6C0BEF56-E407-4176-89D3-A498CBEA671F.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
        saveFileAssertSuccess(
            type: .queueTask,
            fileName: "0F3F3BBB-9C04-4CEE-9267-54FEE574CF4B.json",
            subdirectory: "\(queueSnapshotFilesDirectoryName)/tasks"
        )
    }
}

private extension SampleDataFilesUtil {
    func saveFileAssertSuccess(
        type: FileType,
        fileName: String,
        subdirectory: String
    ) {
        let successfullySavedFile = fileStore.save(
            type: type,
            contents: readFileContents(
                fileName: fileName,
                subdirectory: subdirectory
            ).data,
            fileId: fileName
        )

        if !successfullySavedFile {
            fatalError(
                "File was not successfully saved to the test app bundle. That means the test function will probably fail as the file it depends on would not exist."
            )
        }
    }

    // Read file contents from a static file stored in the Tests/ source code.
    // Thanks, https://useyourloaf.com/blog/add-resources-to-swift-packages/
    func readFileContents(fileName: String, subdirectory: String) -> String {
        let filenameWithoutExtension = String(fileName.split(separator: ".")[0])
        let filenameExtension = String(fileName.split(separator: ".").last!)
        let subdirectory = "\(sampleDataFilesRootDirectoryName)/\(subdirectory)"

        guard let pathString = Bundle.module.url(
            forResource: filenameWithoutExtension,
            withExtension: filenameExtension,
            subdirectory: subdirectory
        ) else {
            fatalError(
                "\(subdirectory)/\(filenameWithoutExtension).\(filenameExtension) not found in Tests/\(subdirectory)"
            )
        }

        return try! String(contentsOf: pathString, encoding: .utf8)
    }
}
