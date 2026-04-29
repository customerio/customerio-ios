import Foundation

/// Supplies the encryption passphrase that SqlCipher uses to derive the
/// AES-256 key for the on-device database.
///
/// The protocol exists so the key-derivation strategy can be swapped without
/// touching call sites. Two concrete implementations are provided:
///
/// - ``ApiKeyDatabaseKeyProvider``: uses the CDP API key directly (default).
/// - ``KeychainDatabaseKeyProvider``: generates a random per-install key and
///   stores it in the iOS/macOS Keychain.
///
/// Conforming types must be `Sendable`; key derivation should be fast and
/// non-blocking, so the method is synchronous.
public protocol DatabaseKeyProvider: Sendable {
    /// Return the passphrase to pass to `Database(path:key:)`.
    ///
    /// - Parameter cdpApiKey: The developer's CDP API key, supplied so
    ///   implementations can scope their output to the current key — i.e. a
    ///   key rotation produces a new database identity automatically.
    func encryptionKey(for cdpApiKey: String) throws -> String
}
