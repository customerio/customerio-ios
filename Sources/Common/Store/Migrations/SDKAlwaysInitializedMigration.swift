import Foundation

/**
 Migration done for SDK always initizlized change we made to the SDK: https://github.com/customerio/issues/issues/10797

 Before this change to the SDK, the SDK sandboxed the SDK data by siteid. The background queue and profile id for profile identified to name a few examples.
 After this change, the SDK stores all of it's SDK data in a single place. The SDK does not support using the SDK with multiple workspaces and therefore, no need to sandbox.

 Run after the SDK has been initialized so we have a site id.
 */
public class SDKAlwaysInitializedMigration: BaseMigration {
    let siteId: String

    let sandboxedFileStorage: SandboxedSiteIdFileStorage
    let sandboxedKeyValueStorage: SandboxedSiteIdKeyValueStorage
    let globalKeyValueStorage: GlobalStoreKeyValueStorage

    let sourceDataDiGraph: DIGraph

    let destinationKeyValueStorage: KeyValueStorage
    let destinationQueueStorage: QueueStorage

    public init(siteId: String, destinationDiGraph: DIGraph) {
        self.siteId = siteId
        self.sandboxedFileStorage = SandboxedSiteIdFileStorage(siteId: siteId, destinationDiGraph: destinationDiGraph)
        self.sourceDataDiGraph = DIGraph(sdkConfig: destinationDiGraph.sdkConfig)
        sourceDataDiGraph.override(value: sandboxedFileStorage, forType: FileStorage.self)

        self.sandboxedKeyValueStorage = SandboxedSiteIdKeyValueStorage(siteId: siteId, destinationDiGraph: destinationDiGraph)
        self.globalKeyValueStorage = GlobalStoreKeyValueStorage(siteId: siteId, destinationDiGraph: destinationDiGraph)

        self.destinationKeyValueStorage = destinationDiGraph.keyValueStorage
        self.destinationQueueStorage = destinationDiGraph.queueStorage

        super.init(migrationName: "sdk-always-initialized", destinationDiGraph: destinationDiGraph)
    }

    override func performMigration() {
        // Migrate key/value storage values
        // We are migrating from sandboxed key/value storage to 1 store for all SDK data.
        destinationKeyValueStorage.migrate(from: sandboxedKeyValueStorage)
        destinationKeyValueStorage.migrate(from: globalKeyValueStorage)

        // Migrate the BQ
        // The BQ might have tasks added to it before the SDK was initialized and the migration executed.
        // Therefore, we should not simply copy BQ tasks (files) from sandboxed file storage to
        // non-sandboxed file storage. Ask the BQ store to do all of the migration so the BQ can lock,
        // perform all migration logic, then unlock.
        destinationQueueStorage.migrate(from: sourceDataDiGraph.queueStorage)
    }
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
 \__ <site-id>/
      \__ queue/
           \__ inventory.json
               tasks/
                \__ <task-uuid>
          images/
           \__ ...
 ```

 Notice that we are using the <site id> as a way to isolate files from each other.
 The file tree remains the same for all site ids.
 */
class SandboxedSiteIdFileStorage: FileManagerFileStorage {
    private let siteId: String

    init(siteId: String, destinationDiGraph: DIGraph) {
        self.siteId = siteId

        super.init(logger: destinationDiGraph.logger)
    }

    // This code is taken from FileStorage implementation class before we stopped sandboxing data.
    // The code in this function should never change. It's purpose is for migrating away from sandboxing.
    override func getRootDirectoryForAllFiles() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // put *all* files into our own "io.customer" directory to isolate files.
        .appendingPathComponent("io.customer", isDirectory: true)
        // isolate all directories by their siteId, first
        .appendingPathComponent(siteId, isDirectory: true)
    }
}

/**
 We used to sandbox all of the SDK's key/value data by siteId. This class is able to read that data that was written before we made this change.
 */
class SandboxedSiteIdKeyValueStorage: UserDefaultsKeyValueStorage {
    private let siteId: String
    private let deviceMetricsGrabber: DeviceMetricsGrabber

    init(siteId: String, destinationDiGraph: DIGraph) {
        self.siteId = siteId
        self.deviceMetricsGrabber = destinationDiGraph.deviceMetricsGrabber

        super.init()
    }

    // This code is taken from KeyValueStorage implementation class before we stopped sandboxing data.
    // The code in this function should never change. It's purpose is for migrating away from sandboxing.
    override func getStorageName() -> String {
        var appUniqueIdentifier = ""
        if let appBundleId = deviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        return "io.customer.sdk\(appUniqueIdentifier).\(siteId)"
    }
}

class GlobalStoreKeyValueStorage: UserDefaultsKeyValueStorage {
    private let siteId: String
    private let deviceMetricsGrabber: DeviceMetricsGrabber

    init(siteId: String, destinationDiGraph: DIGraph) {
        self.siteId = siteId
        self.deviceMetricsGrabber = destinationDiGraph.deviceMetricsGrabber

        super.init()
    }

    // This code is taken from KeyValueStorage implementation class before we stopped sandboxing data.
    // The code in this function should never change. It's purpose is for migrating away from sandboxing.
    override func getStorageName() -> String {
        var appUniqueIdentifier = ""
        if let appBundleId = deviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        return "io.customer.sdk\(appUniqueIdentifier).shared"
    }
}
