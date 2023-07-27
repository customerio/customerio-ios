import Foundation

public protocol Migration {
    var migrationName: String { get }

    func run()
}

public class BaseMigration: Migration {
    public let migrationName: String

    let keyValueStorage: KeyValueStorage

    public init(migrationName: String, destinationDiGraph: DIGraph) {
        self.migrationName = migrationName

        self.keyValueStorage = destinationDiGraph.keyValueStorage
    }

    public func run() {
        var listOfMigrationsRun = keyValueStorage.stringList(.migrationsRun) ?? []

        guard !listOfMigrationsRun.contains(migrationName) else {
            return
        }

        performMigration()

        listOfMigrationsRun.append(migrationName)
        keyValueStorage.setStringList(listOfMigrationsRun, forKey: .migrationsRun)
    }

    func performMigration() {
        fatalError("Must override in subclass")
    }
}
