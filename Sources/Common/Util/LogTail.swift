import Foundation

/// Builds the key tail some log lines end with, which tools that read the SDK's logs parse
/// (cio-sdk-tools `verify push`, see its `docs/verify-contract.md`):
///
/// ```
/// [Push] Tracking push message opened with deliveryId: dgS_abc || ev=push.opened id=dgS_abc
/// ```
///
/// The sentence in front is for people and stays as it is; the tail is the contract. Never rename an `ev` or a key, or
/// change what a value means. Adding a key is fine.
public enum LogTail {
    /// Readers split a line on the **last** occurrence, then each pair on its **first** `=`, then decode the value.
    public static let separator = " || "

    /// The value of a delivery id, token or key the SDK holds none of.
    public static let none = "none"

    /// - Parameters:
    ///   - event: The `ev` value, always written first.
    ///   - fields: Lowercase `[a-z_]+` keys, written in this order. A `nil` value leaves its key out.
    public static func make(_ event: String, _ fields: KeyValuePairs<String, String?> = [:]) -> String {
        var pairs = ["ev=\(encode(event))"]
        for (key, value) in fields {
            guard let value else { continue }
            pairs.append("\(key)=\(encode(value))")
        }
        return separator + pairs.joined(separator: " ")
    }

    /// `value`, or `none` when it's `nil` or empty.
    public static func orNone(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return none }
        return value
    }

    /// Percent-encodes `%`, `|` and every whitespace character as their UTF-8 bytes (`%XX`, uppercase hex), so a value
    /// can never contain the separator. Everything else, `=` included, stays literal.
    public static func encode(_ value: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            if scalar == "%" || scalar == "|" || scalar.properties.isWhitespace {
                for byte in String(scalar).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            } else {
                encoded.unicodeScalars.append(scalar)
            }
        }
        return encoded
    }
}
