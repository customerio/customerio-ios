import Foundation

/// Reads a log line the way cio-sdk-tools `verify push` does (its `docs/verify-contract.md`): split on the **last**
/// ` || `, then each pair on its **first** `=`, then percent-decode the value. Written from the reader's rules, not
/// from the SDK's `LogTail`, so the tests catch the builder drifting from them.
public struct LogTailReader {
    /// Everything in front of the tail.
    public let sentence: String
    /// The keys in the order they're written, `ev` first.
    public let keys: [String]
    /// Decoded values by key, `ev` included.
    public let values: [String: String]

    public var event: String? { values["ev"] }

    public init?(_ line: String) {
        guard let separator = line.range(of: " || ", options: .backwards) else { return nil }
        var keys: [String] = []
        var values: [String: String] = [:]
        for pair in line[separator.upperBound...].split(separator: " ", omittingEmptySubsequences: false) {
            guard let equals = pair.firstIndex(of: "="),
                  let value = String(pair[pair.index(after: equals)...]).removingPercentEncoding
            else { return nil }
            let key = String(pair[..<equals])
            keys.append(key)
            values[key] = value
        }
        guard keys.first == "ev" else { return nil }

        self.sentence = String(line[..<separator.lowerBound])
        self.keys = keys
        self.values = values
    }
}
