@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Captures formatted log messages verbatim, and reads the machine tail back off them.
///
/// Extracted from `GeofenceLogTailTests`, which owns the producer-side contract, so that the
/// scenario replay harness can consume the same records without a second parser. Two parsers for
/// one untyped string contract is how the contract drifts: the tests would keep passing against
/// their own reading of the tail while replay asserted against a different one.
///
/// Deliberately not `LoggerMock` — the generated mock records invocation counts, and what both
/// callers need is the exact string.
final class CapturingLogger: Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        captured.removeAll()
    }

    var logLevel: CioLogLevel = .debug
    func setLogDispatcher(_: ((CioLogLevel, String) -> Void)?) {}
    func setLogLevel(_ level: CioLogLevel) {
        logLevel = level
    }

    func debug(_ message: String, _ tag: String?) {
        record(message, tag)
    }

    func info(_ message: String, _ tag: String?) {
        record(message, tag)
    }

    /// Mirrors `LoggerImpl.formatMessage`, which appends the description to the **whole** message.
    /// A double that quietly dropped the error let a record ship whose tail was no longer last,
    /// and every assertion passed anyway.
    func error(_ message: String, _ tag: String?, _ error: Error?) {
        record(error.map { "\(message) Error: \($0.localizedDescription)" } ?? message, tag)
    }

    private func record(_ message: String, _ tag: String?) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(tag.map { "[\($0)] \(message)" } ?? message)
    }
}

/// Reads the ` || ev=… k=v` tail off a formatted message.
///
/// Mirrors what the off-device parser does: split on the **last** delimiter, then accept the
/// remainder only if every token is a `key=value` pair. Splitting on the first delimiter would
/// mis-read any record whose prose contains one.
enum GeofenceTail {
    static func parse(_ message: String) -> [String: String]? {
        guard let range = message.range(of: GeofenceLog.delimiter, options: .backwards) else { return nil }
        let tail = String(message[range.upperBound...])
        var fields: [String: String] = [:]
        for token in tail.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            fields[String(parts[0])] = String(parts[1])
        }
        return fields.isEmpty ? nil : fields
    }

    /// Every parseable tail in a capture, in emission order. The unit the matcher walks.
    static func parseAll(_ messages: [String]) -> [[String: String]] {
        messages.compactMap { parse($0) }
    }
}
