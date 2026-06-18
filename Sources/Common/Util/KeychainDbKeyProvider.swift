import Foundation
import Security

/// Provides a per-account database encryption key persisted in the system Keychain.
public protocol DbKeyProvider: AutoMockable {
    /// Returns the existing database encryption key for `account`, generating and
    /// persisting a new cryptographically random key if none exists yet.
    func getOrCreateDbKey(account: String) throws -> String
}

// sourcery: InjectRegisterShared = "DbKeyProvider"
// sourcery: InjectSingleton
/// Keychain-backed implementation of ``DbKeyProvider``.
///
/// On first call for a given account, generates a 32-byte random key (hex-encoded)
/// and stores it as a `kSecClassGenericPassword` item under
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. This allows the key to
/// survive app restarts and be accessible during background tasks, while never
/// leaving the device via iCloud or backups.
public struct KeychainDbKeyProvider: DbKeyProvider, @unchecked Sendable {
    private static let service = "io.customer.sdk.dbkey"
    private let lock = NSLock()

    public init() {}

    public func getOrCreateDbKey(account: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = try loadKey(account: account) {
            return existing
        }
        let newKey = try generateKey()
        try storeKey(newKey, account: account)
        return newKey
    }

    /// Removes the key for the given account. Intended for test cleanup only.
    func deleteKey(account: String) {
        lock.lock()
        defer { lock.unlock() }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadKey(account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainDbKeyError.readFailed(status: status)
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainDbKeyError.invalidData
        }
        return key
    }

    private func storeKey(_ key: String, account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainDbKeyError.invalidData
        }
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainDbKeyError.writeFailed(status: status)
        }
    }

    private func generateKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainDbKeyError.keyGenerationFailed(status: status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum KeychainDbKeyError: Error {
    case readFailed(status: OSStatus)
    case writeFailed(status: OSStatus)
    case keyGenerationFailed(status: OSStatus)
    case invalidData
}
