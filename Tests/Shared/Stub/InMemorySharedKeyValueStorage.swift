import CioInternalCommon
import Foundation

/// In-memory implementation of SharedKeyValueStorage for tests. Does not persist across runs.
public final class InMemorySharedKeyValueStorage: SharedKeyValueStorage {
    private var ints: [KeyValueStorageKey: Int] = [:]
    private var doubles: [KeyValueStorageKey: Double] = [:]
    private var strings: [KeyValueStorageKey: String] = [:]
    private var dates: [KeyValueStorageKey: Date] = [:]
    private var dataValues: [KeyValueStorageKey: Data] = [:]

    public init() {}

    public func integer(_ key: KeyValueStorageKey) -> Int? {
        ints[key]
    }

    public func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        ints[key] = value
    }

    public func double(_ key: KeyValueStorageKey) -> Double? {
        doubles[key]
    }

    public func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        doubles[key] = value
    }

    public func string(_ key: KeyValueStorageKey) -> String? {
        strings[key]
    }

    public func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        strings[key] = value
    }

    public func date(_ key: KeyValueStorageKey) -> Date? {
        dates[key]
    }

    public func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        dates[key] = value
    }

    public func data(_ key: KeyValueStorageKey) -> Data? {
        dataValues[key]
    }

    public func setData(_ value: Data?, forKey key: KeyValueStorageKey) {
        dataValues[key] = value
    }

    public func deleteAll() {
        ints.removeAll()
        doubles.removeAll()
        strings.removeAll()
        dates.removeAll()
        dataValues.removeAll()
    }
}
