import Foundation

/// Reads the prefix of Customer.io API keys: `{type}_{us|eu}_...`.
/// `sk_` keys are secret and must never ship in an app, `pk_` keys are public.
/// Legacy keys have no prefix. The server validates the rest of the key.
public enum ApiKey {
    public static let secretKeyError = "Secret (sk_) keys must not be used in apps. Use your public key in apps."

    /// `true` for secret `sk_` keys.
    public static func isSecret(_ key: String) -> Bool {
        key.hasPrefix("sk_")
    }

    /// `true` for public `pk_` keys.
    public static func isPublic(_ key: String) -> Bool {
        key.hasPrefix("pk_")
    }

    /// Region in the key prefix, or `nil` for legacy keys.
    public static func region(of key: String) -> Region? {
        prefix(of: key).map { Region.getRegion(from: String($0.region)) }
    }

    /// Parses keys shaped `^[a-z]{2}_(us|eu)_`, so the region works for any key type.
    private static func prefix(of key: String) -> (kind: Substring, region: Substring)? {
        let parts = key.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 2,
              parts[0].allSatisfy({ ("a" ... "z").contains($0) }),
              ["us", "eu"].contains(parts[1])
        else {
            return nil
        }
        return (parts[0], parts[1])
    }
}
