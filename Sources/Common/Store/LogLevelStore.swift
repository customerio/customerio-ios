import Foundation

/// Keeps the log level the app's SDK initialization resolved, so a process the OS starts for a push or a tap logs at
/// that level before the app initializes the SDK. Wrapper SDKs initialize late, from JS or Dart.
///
/// Only `CustomerIO.initialize` saves, and an app extension can't call it. The storage is the SDK's own `UserDefaults`
/// suite, named after the process's bundle id and not shared through an App Group, so a Notification Service
/// Extension neither reads nor overwrites the app's level.
public protocol LogLevelStore: AutoMockable {
    /// The level the app's last SDK initialization resolved, `nil` until the app first initializes the SDK.
    var logLevel: CioLogLevel? { get }
    /// Saves the level the app's SDK initialization resolved, explicit or default.
    func saveLogLevel(_ level: CioLogLevel)
}

// sourcery: InjectRegisterShared = "LogLevelStore"
public class CioLogLevelStore: LogLevelStore {
    private let keyValueStorage: SharedKeyValueStorage

    init(keyValueStorage: SharedKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public var logLevel: CioLogLevel? {
        keyValueStorage.string(.logLevel).flatMap(CioLogLevel.getLogLevel(for:))
    }

    public func saveLogLevel(_ level: CioLogLevel) {
        keyValueStorage.setString(level.rawValue, forKey: .logLevel)
    }
}
