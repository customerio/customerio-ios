import Foundation

/// A ``DatabaseKeyProvider`` that uses the CDP API key directly as the
/// SqlCipher passphrase.
///
/// This is the default provider. The same API key is embedded in every
/// binary shipped for that workspace, so the database is app-scoped but not
/// device-scoped — the effective security model is file-at-rest protection
/// against an attacker who has the raw `.db` file but not the app binary.
///
/// Use ``KeychainDatabaseKeyProvider`` when you want a per-install random key
/// that is hardware-bound and inaccessible even to someone with the binary.
public struct ApiKeyDatabaseKeyProvider: DatabaseKeyProvider {

    public init() {}

    /// Returns `cdpApiKey` unchanged.
    public func encryptionKey(for cdpApiKey: String) throws -> String {
        cdpApiKey
    }
}
