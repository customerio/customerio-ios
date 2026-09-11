@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Captures formatted log messages verbatim, and reads the machine tail back off them.
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

    /// Mirrors `LoggerImpl.formatMessage`: the error description goes after the whole message.
    func error(_ message: String, _ tag: String?, _ error: Error?) {
        record(error.map { "\(message) Error: \($0.localizedDescription)" } ?? message, tag)
    }

    private func record(_ message: String, _ tag: String?) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(tag.map { "[\($0)] \(message)" } ?? message)
    }
}

/// Reads the ` || ev=… k=v` tail off a formatted message: split on the last delimiter, accept
/// only if every token is `key=value`.
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

    /// Every parseable tail, in emission order.
    static func parseAll(_ messages: [String]) -> [[String: String]] {
        messages.compactMap { parse($0) }
    }
}
