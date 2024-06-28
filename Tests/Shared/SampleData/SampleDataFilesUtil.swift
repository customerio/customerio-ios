import CioInternalCommon
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
//
// In order to obtain sample files:
// 1. Plug iPhone into your Computer.
// 2. Run a sample iPhone app to make it save files that you care about into the app's file storage.
// 3. Open Xcode > Window > Devices and Simulators > Select your iPhone that's plugged in > Select app in Installed App
// section > Select "..." icon > Download container.
// 4. You can now browse the files saved to the app. Copy and paste files from there that you care about.
public class SampleDataFilesUtil {
    private let fileStore: FileStorage

    public init(fileStore: FileStorage) {
        self.fileStore = fileStore
    }

    private let sampleDataFilesRootDirectoryName = "SampleDataFiles"
}

extension SampleDataFilesUtil {
    func saveFilesInDirectoryAssertSuccess(
        siteId: String,
        type: FileType,
        fileNames: [String],
        subdirectory: String?
    ) {
        fileNames.forEach { fileName in
            saveFileAssertSuccess(siteId: siteId, type: type, fileName: fileName, subdirectory: subdirectory)
        }
    }

    func saveFileAssertSuccess(
        siteId: String,
        type: FileType,
        fileName: String,
        subdirectory: String?
    ) {
        let successfullySavedFile = fileStore.save(
            siteId: siteId,
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
    func readFileContents(fileName: String, subdirectory: String?) -> String {
        let filenameWithoutExtension = String(fileName.split(separator: ".")[0])
        let filenameExtension = String(fileName.split(separator: ".").last!)
        var directoryToSaveFiles = sampleDataFilesRootDirectoryName
        if let subdirectory = subdirectory {
            directoryToSaveFiles += "/\(subdirectory)"
        }

        guard let pathString = Bundle.module.url(
            forResource: filenameWithoutExtension,
            withExtension: filenameExtension,
            subdirectory: directoryToSaveFiles
        ) else {
            fatalError(
                "\(directoryToSaveFiles)/\(filenameWithoutExtension).\(filenameExtension) not found in Tests/\(directoryToSaveFiles)"
            )
        }

        guard let fileContentsString = try? String(contentsOf: pathString, encoding: .utf8) else {
            fatalError("File \(pathString.absoluteString) not able to read it as a String")
        }

        return fileContentsString
    }
}
