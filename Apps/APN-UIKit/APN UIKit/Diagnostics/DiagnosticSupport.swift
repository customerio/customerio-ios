import Darwin
import Foundation

// MARK: - Concurrency

/// Holds a non-`Sendable` value behind its own lock.
final class DiagnosticLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }
}

// MARK: - Clocks

/// Every record carries both a wall clock and a monotonic clock.
enum DiagnosticClock {
    /// Nanoseconds since boot, **including** time the device spent asleep.
    static func monotonicNanos() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC)
    }

    /// A stable identifier for the current boot, so `mono` values from two processes can be told
    /// apart from `mono` values across a reboot.
    static func bootIdentifier() -> String {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let boot = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        return iso8601(boot)
    }

    private static let formatter = DiagnosticLocked<ISO8601DateFormatter>({
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        return formatter
    }())

    /// ISO 8601 with milliseconds and a local UTC offset. The offset is deliberate — a drive log
    /// is read next to a route recorded in local time.
    static func iso8601(_ date: Date) -> String {
        formatter.withValue { $0.string(from: date) }
    }
}

// MARK: - JSON

/// Minimal JSON string encoding.
enum DiagnosticJSON {
    /// Encodes a Swift string as a complete JSON string literal, quotes included.
    static func string(_ value: String) -> String {
        var out = "\""
        out.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                // Control characters have no literal form and would produce a file that no parser
                // will read. Anything else, including the whole of Unicode above U+001F, is legal
                // inside a JSON string as-is.
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
