import Foundation
import Security
import Testing

@testable import CustomerIO_Utilities

// MARK: - Helpers

/// Returns a unique service name so every test gets a completely isolated
/// keychain namespace. Items written here are never seen by other tests, and
/// the cleanup helper deletes them by the same service name.
private func uniqueService() -> String {
    "cio-test-\(UUID().uuidString)"
}

/// Delete all generic-password items stored under `serviceName`.
/// Called in `defer` blocks so keychain items don't accumulate between runs.
private func deleteAllItems(serviceName: String) {
    let query: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: serviceName,
    ]
    SecItemDelete(query as CFDictionary)
}

// MARK: - KeychainDatabaseKeyProvider

@Suite struct KeychainDatabaseKeyProviderTests {

    // MARK: Basic key generation

    @Test func generatesANonEmptyKey() throws {
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let key = try provider.encryptionKey(for: "api-key-1")
        #expect(!key.isEmpty)
    }

    @Test func generatedKeyIsHexString() throws {
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let key = try provider.encryptionKey(for: "api-key-1")
        let isHex = key.allSatisfy { $0.isHexDigit }
        #expect(isHex)
    }

    @Test func generatedKeyIs64Characters() throws {
        // 32 bytes → 64 hex characters
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let key = try provider.encryptionKey(for: "api-key-1")
        #expect(key.count == 64)
    }

    // MARK: Idempotency — same key returned on subsequent calls

    @Test func returnsTheSameKeyOnSecondCall() throws {
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let first  = try provider.encryptionKey(for: "stable-key")
        let second = try provider.encryptionKey(for: "stable-key")
        #expect(first == second)
    }

    @Test func returnsTheSameKeyFromFreshProviderInstance() throws {
        // Two separate provider instances sharing the same serviceName must
        // agree on the key — simulating an app restart.
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let key1 = try KeychainDatabaseKeyProvider(serviceName: service)
            .encryptionKey(for: "shared-api-key")
        let key2 = try KeychainDatabaseKeyProvider(serviceName: service)
            .encryptionKey(for: "shared-api-key")
        #expect(key1 == key2)
    }

    // MARK: API key isolation — different cdpApiKey → different keychain item

    @Test func differentApiKeysProduceDifferentKeys() throws {
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let keyA = try provider.encryptionKey(for: "api-key-A")
        let keyB = try provider.encryptionKey(for: "api-key-B")
        #expect(keyA != keyB)
    }

    @Test func eachApiKeyIsPersisted() throws {
        // Both keys should survive being read back after the other was written.
        let service = uniqueService()
        defer { deleteAllItems(serviceName: service) }

        let provider = KeychainDatabaseKeyProvider(serviceName: service)
        let keyA = try provider.encryptionKey(for: "api-key-A")
        let keyB = try provider.encryptionKey(for: "api-key-B")

        // Read them again — must match first reads
        let keyA2 = try provider.encryptionKey(for: "api-key-A")
        let keyB2 = try provider.encryptionKey(for: "api-key-B")
        #expect(keyA == keyA2)
        #expect(keyB == keyB2)
    }

    // MARK: Service name isolation

    @Test func differentServiceNamesDoNotShareKeys() throws {
        let serviceX = uniqueService()
        let serviceY = uniqueService()
        defer {
            deleteAllItems(serviceName: serviceX)
            deleteAllItems(serviceName: serviceY)
        }

        let keyX = try KeychainDatabaseKeyProvider(serviceName: serviceX)
            .encryptionKey(for: "same-api-key")
        let keyY = try KeychainDatabaseKeyProvider(serviceName: serviceY)
            .encryptionKey(for: "same-api-key")

        // Random keys generated independently must differ with overwhelming probability
        #expect(keyX != keyY)
    }

    // MARK: Randomness

    @Test func freshInstallsProduceDifferentKeys() throws {
        // Two services (simulating two installs) should get independent keys.
        let serviceA = uniqueService()
        let serviceB = uniqueService()
        defer {
            deleteAllItems(serviceName: serviceA)
            deleteAllItems(serviceName: serviceB)
        }

        let keyA = try KeychainDatabaseKeyProvider(serviceName: serviceA)
            .encryptionKey(for: "api-key")
        let keyB = try KeychainDatabaseKeyProvider(serviceName: serviceB)
            .encryptionKey(for: "api-key")

        #expect(keyA != keyB)
    }

    // MARK: ApiKeyDatabaseKeyProvider (companion type, trivial)

    @Test func apiKeyProvider_returnsKeyUnchanged() throws {
        let provider = ApiKeyDatabaseKeyProvider()
        #expect(try provider.encryptionKey(for: "my-cdp-key") == "my-cdp-key")
    }

    @Test func apiKeyProvider_emptyKeyPassedThrough() throws {
        let provider = ApiKeyDatabaseKeyProvider()
        #expect(try provider.encryptionKey(for: "") == "")
    }
}
