@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Captures carry real coordinates and fence names: none may become a committed fixture.
/// Values stay `String`: typing them here would invent a second schema beside the tail's.
struct Scenario {
    let name: String
    let platform: String
    let header: Header
    let records: [Record]

    struct Header {
        let name: String
        let platform: String
        /// Absent becomes `unknown` and is rejected: defaulting to `recorded` would let authored
        /// scenarios satisfy the "any drive found?" guard.
        let sourceKind: String
        let startedAt: String
        let sdk: String?
        let device: String?
    }

    /// Only for the "any drive found?" guard; `platform` alone decides where a scenario runs.
    var isRecorded: Bool { header.sourceKind == "recorded" }

    struct Record {
        enum Kind: String {
            case given
            case when
            case then
            /// Neither an input nor an assertion.
            case note
        }

        let kind: Kind
        let at: TimeInterval
        let ev: String
        let fields: [String: String]

        /// A single-fence Android `ids` is the same event; a batched one stays unsupported.
        var fenceId: String? {
            if let id = fields["id"] { return id }
            guard let ids = fields["ids"], !ids.contains(",") else { return nil }
            return ids
        }

        var transition: GeofenceTransition? { fields["t"].flatMap(GeofenceTransition.init(rawValue:)) }

        /// Stimuli only; the transform strips it from expectations.
        var accuracy: String? { fields["acc"] }

        var reason: String? { fields["why"] }
    }

    /// Optional: a synthetic scenario's `t0` is free text.
    var startedAt: Date? { ISO8601DateFormatter.geofenceScenario.date(from: header.startedAt) }

    var given: [Record] { records.filter { $0.kind == .given } }
    var when: [Record] { records.filter { $0.kind == .when } }
    var then: [Record] { records.filter { $0.kind == .then } }
    var note: [Record] { records.filter { $0.kind == .note } }
}

enum ScenarioLoader {
    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case missingHeader
        case malformedLine(Int, String)

        var description: String {
            switch self {
            case .unreadable(let path): "cannot read scenario at \(path)"
            case .missingHeader: "first record is not k=scenario"
            case .malformedLine(let n, let why): "line \(n): \(why)"
            }
        }
    }

    static func load(path: String) throws -> Scenario {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { throw LoadError.unreadable(path) }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> Scenario {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first,
              let head = try json(first, line: 1) as? [String: Any],
              head["k"] as? String == "scenario"
        else { throw LoadError.missingHeader }

        let header = Scenario.Header(
            name: head["name"] as? String ?? "unnamed",
            platform: head["platform"] as? String ?? "unknown",
            sourceKind: (head["source"] as? [String: Any])?["kind"] as? String ?? "unknown",
            startedAt: head["t0"] as? String ?? "",
            sdk: head["sdk"] as? String,
            device: head["device"] as? String
        )

        var records: [Scenario.Record] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            let number = offset + 2
            guard let object = try json(line, line: number) as? [String: Any] else {
                throw LoadError.malformedLine(number, "not a JSON object")
            }
            guard let rawKind = object["k"] as? String, let kind = Scenario.Record.Kind(rawValue: rawKind) else {
                throw LoadError.malformedLine(number, "unknown kind '\(object["k"] ?? "nil")'")
            }
            guard let ev = object["ev"] as? String else {
                throw LoadError.malformedLine(number, "no ev")
            }
            // Required: defaulting it to 0 would silently reorder the run.
            guard let at = object["at"] as? Double else {
                throw LoadError.malformedLine(number, "no at")
            }
            var fields: [String: String] = [:]
            for (key, value) in object where !["k", "at", "ev"].contains(key) {
                fields[key] = stringify(value)
            }
            records.append(.init(kind: kind, at: at, ev: ev, fields: fields))
        }

        return Scenario(name: header.name, platform: header.platform, header: header, records: records)
    }

    /// Rendered as the tail prints it, so a field compares equal to the emitted string.
    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if value is NSNull { return "null" }
        // `String(describing:)` would give a debug description the runner can't parse back.
        if value is [Any] || value is [String: Any] {
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let json = String(data: data, encoding: .utf8)
            else { return String(describing: value) }
            return json
        }
        guard let number = value as? NSNumber else { return String(describing: value) }
        // `as? Bool` matches 1 too; only the CF type id tells a JSON boolean from a number.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        let double = number.doubleValue
        // The tail prints whole floats with one decimal (`acc=14.0`) and integers bare (`n=1`).
        if String(cString: number.objCType) == "d" || String(cString: number.objCType) == "f" {
            return double == double.rounded() && abs(double) < 1e15
                ? String(format: "%.1f", double)
                : String(double)
        }
        return String(number.int64Value)
    }

    private static func json(_ line: String, line number: Int) throws -> Any {
        guard let data = line.data(using: .utf8) else {
            throw LoadError.malformedLine(number, "not utf8")
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LoadError.malformedLine(number, "invalid JSON: \(error.localizedDescription)")
        }
    }
}

extension ISO8601DateFormatter {
    /// The transform writes `t0` with fractional seconds and an offset (`2026-09-10T12:45:55.899+04:00`).
    static let geofenceScenario: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
