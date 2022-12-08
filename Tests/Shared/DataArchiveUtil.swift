import Common
import Foundation
import XCTest

public class DataArchiveUtil {
    public init() {}

    public func saveSdkV1QueueFiles(
        fileStore: FileStorage,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        saveFile(
            fileStore: fileStore,
            type: .queueInventory,
            fileName: "inventory",
            subdirectory: "DataArchive/V1QueueSnapshot",
            fileExtension: "json",
            file: file,
            line: line
        )

        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "FD677E99-B774-4B12-A30A-B2315D497D36",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "DD1F8FE7-ADDB-4015-849F-4BBD0E537A2C",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "D687EAA8-396F-4DEE-B983-B8CFF723A1B2",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "BDE6D050-3A26-4A4D-B923-B1C52901090E",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "AA6418AC-40D0-4580-93B9-C6262257BAA3",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "A4E62708-F263-4562-8503-CB55B4AE8E39",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "3143DAD0-E28A-42E6-84B1-D9F6779DCF91",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "940DDFFB-BDC6-4452-8895-A43906E75FC2",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "8C686475-FDD4-44BE-B423-B974D4EDF83A",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "6C0BEF56-E407-4176-89D3-A498CBEA671F",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
        saveFile(
            fileStore: fileStore,
            type: .queueTask,
            fileName: "0F3F3BBB-9C04-4CEE-9267-54FEE574CF4B",
            subdirectory: "DataArchive/V1QueueSnapshot/tasks",
            fileExtension: "json",
            file: file,
            line: line
        )
    }
}

private extension DataArchiveUtil {
    func saveFile(
        fileStore: FileStorage,
        type: FileType,
        fileName: String,
        subdirectory: String,
        fileExtension: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertTrue(
            fileStore
                .save(
                    type: type,
                    contents: readFileContents(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        subdirectory: subdirectory
                    )
                    .data,
                    fileId: "\(fileName).\(fileExtension)"
                ),
            file: file,
            line: line
        )
    }

    func readFileContents(fileName: String, fileExtension: String, subdirectory: String) -> String {
        guard let pathString = Bundle.module.url(
            forResource: fileName,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            fatalError("\(fileName).\(fileExtension) not found in tests source code")
        }

        return try! String(contentsOf: pathString, encoding: .utf8)
    }
}
