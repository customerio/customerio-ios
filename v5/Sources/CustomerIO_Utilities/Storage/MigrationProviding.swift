import SqlCipherKit

/// A module that needs to extend the SDK's database schema implements this protocol
/// and declares its migrations. `CustomerIO.configure()` collects them and passes
/// them as `extra:` to `StorageManager.runMigrations(extra:)` before any module
/// is configured, ensuring tables exist by the time `configure` is called.
public protocol MigrationProviding {
    var additionalMigrations: [any Migration] { get }
}
