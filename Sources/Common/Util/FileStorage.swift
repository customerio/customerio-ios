import Foundation

public struct SdkFile {
    let type: FileType
    let directoryPath: URL
    let filePath: URL
}

public protocol FileStorage: AutoMockable {
    /// return `true` if the save was successful and no errors were caught/logged
    /// `fileId` - the file name. `nil` if
    func save(type: FileType, contents: Data, fileId: String?) -> Bool
    /// return `nil` if an error was caught and logged *or* if the file simply doesn't exist
    func get(type: FileType, fileId: String?) -> Data?
    func delete(type: FileType, fileId: String) -> Bool
}

public enum FileType {
    case queueInventory
    case queueTask
}

/*
 Save data to a file on the device file system.

 Responsibilities:
 * Be able to mock so we can use in unit tests without using the real file system
 * Be the 1 source of truth for where certain types of files are stored.
   Making code less prone to errors and typos for file paths.

 Way that files are stored in this class:
 ```
 FileManager.SearchPath
 \__ queue/
     \__ inventory.json
         tasks/
             \__ <task-uuid>
     images/
          \__ ...
 ```
 */
// sourcery: InjectRegister = "FileStorage"
public class FileManagerFileStorage: FileStorage {
    let fileManager = FileManager.default
    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func save(type: FileType, contents: Data, fileId: String?) -> Bool {
        do {
            guard let saveLocationUrl = try getPathToFile(type: type, fileId: fileId) else { return false }

            try contents.write(to: saveLocationUrl)

            return true
        } catch {
            logger.error(error.localizedDescription)
            return false
        }
    }

    public func get(type: FileType, fileId: String?) -> Data? {
        do {
            guard let saveLocationUrl = try getPathToFile(type: type, fileId: fileId) else { return nil }

            return try? Data(contentsOf: saveLocationUrl)
        } catch {
            logger.error(error.localizedDescription)
            return nil
        }
    }

    public func delete(type: FileType, fileId: String) -> Bool {
        do {
            guard let urlFileToDelete = try getPathToFile(type: type, fileId: fileId) else { return false }

            try fileManager.removeItem(at: urlFileToDelete)

            return true
        } catch {
            logger.error(error.localizedDescription)
            return false
        }
    }

    open func getRootDirectoryForAllFiles() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // put *all* files into our own "io.customer" directory to isolate files.
        .appendingPathComponent("io.customer", isDirectory: true)
    }

    private func getDirectoryPathToFile(type fileType: FileType, fileId: String?) throws -> URL? {
        switch fileType {
        case .queueInventory:
            return try getRootDirectoryForAllFiles()
                .appendingPathComponent("queue", isDirectory: true)
        case .queueTask:
            return try getRootDirectoryForAllFiles()
                .appendingPathComponent("queue", isDirectory: true)
                .appendingPathComponent("tasks", isDirectory: true)
        }
    }

    private func getFilePathToFile(directoryPath: URL, type fileType: FileType, fileId: String?) throws -> URL? {
        switch fileType {
        case .queueInventory:
            return directoryPath.appendingPathComponent("inventory.json", isDirectory: false)
        case .queueTask:
            guard let fileId = fileId else {
                return nil
            }

            return directoryPath.appendingPathExtension("\(fileId).json")
        }
    }

    internal func getPathToFile(type fileType: FileType, fileId: String?) throws -> URL? {
        guard let fileDirectoryPath = try getDirectoryPathToFile(type: fileType, fileId: fileId) else {
            return nil
        }

        try fileManager.createDirectory(at: fileDirectoryPath, withIntermediateDirectories: true, attributes: nil)

        guard let filePath = try getFilePathToFile(directoryPath: fileDirectoryPath, type: fileType, fileId: fileId) else {
            return nil
        }

        return filePath
    }
}
