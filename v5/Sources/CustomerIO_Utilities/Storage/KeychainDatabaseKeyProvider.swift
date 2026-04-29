import Foundation
import Security

/// A ``DatabaseKeyProvider`` that stores a random 32-byte hex key in the
/// platform Keychain, generating it on first use.
///
/// ### Key isolation
///
/// The Keychain item's `kSecAttrAccount` is set to `"cio-db-key-<cdpApiKey>"`
/// so that rotating the CDP API key automatically causes a fresh key to be
/// generated — the old database becomes inaccessible and the SDK starts from
/// a clean state, matching the behaviour of the database filename also being
/// scoped to the API key.
///
/// ### Security properties
///
/// - The key is 32 bytes (256 bits) from `SecRandomCopyBytes`, which draws
///   from the Secure Enclave entropy source on supported hardware.
/// - `kSecAttrAccessible` is set to `.afterFirstUnlock` so the key is
///   available after the first authentication post-boot but is protected
///   while the device is locked. This matches the typical SDK use pattern
///   (background uploads after first unlock) while keeping the key encrypted
///   at rest in the Secure Enclave-backed Keychain.
/// - The key is stored under `kSecClassGenericPassword` using the app's
///   bundle identifier as the service name.
public struct KeychainDatabaseKeyProvider: DatabaseKeyProvider {

    /// Bundle identifier used as the Keychain service name.
    /// Defaults to the main bundle identifier; override in tests.
    public let serviceName: String

    public init(serviceName: String = Bundle.main.bundleIdentifier ?? "com.customerio.sdk") {
        self.serviceName = serviceName
    }

    // MARK: - DatabaseKeyProvider

    public func encryptionKey(for cdpApiKey: String) throws -> String {
        let account = "cio-db-key-\(cdpApiKey)"

        // Return an existing key if one was previously generated.
        if let existing = try readFromKeychain(account: account) {
            return existing
        }

        // Generate a fresh 32-byte (256-bit) random key.
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.randomGenerationFailed(status: status)
        }
        let key = bytes.map { String(format: "%02x", $0) }.joined()

        try writeToKeychain(account: account, key: key)
        return key
    }

    // MARK: - Private helpers

    private func readFromKeychain(account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      serviceName,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8)
            else { throw KeychainError.unexpectedData }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status: status)
        }
    }

    private func writeToKeychain(account: String, key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        let item: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      serviceName,
            kSecAttrAccount:      account,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status: status)
        }
    }
}

// MARK: - Errors

public enum KeychainError: Error {
    case randomGenerationFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case writeFailed(status: OSStatus)
    case unexpectedData
}
