import Foundation

/// Reads the prefix of Customer.io API keys: `{ak|wk}_{us|eu}_...`.
/// `ak_` keys are secret and must never ship in an app, `wk_` keys are public.
/// Legacy keys have no prefix. The server validates the rest of the key.
public enum ApiKey {
    public static let secretKeyError = "Secret (ak_) keys must not be used in apps. Use your public key in apps."

    /// `true` for secret `ak_` keys.
    public static func isSecret(_ key: String) -> Bool {
        key.hasPrefix("ak_")
    }

    /// `true` for public `wk_` keys.
    public static func isPublic(_ key: String) -> Bool {
        prefix(of: key)?.kind == "wk"
    }

    /// Region in the key prefix, or `nil` for legacy keys.
    public static func region(of key: String) -> Region? {
        prefix(of: key).map { Region.getRegion(from: String($0.region)) }
    }

    private static func prefix(of key: String) -> (kind: Substring, region: Substring)? {
        let parts = key.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, ["ak", "wk"].contains(parts[0]), ["us", "eu"].contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }
}
