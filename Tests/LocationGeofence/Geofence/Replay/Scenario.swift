@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// A replayable scenario: fixtures to seed, stimuli to inject, expectations to match.
///
/// One NDJSON record per line, each tagged with a kind. The format and its rationale live in
/// `geofence-scenario-format-decision.md`; the scenarios these load live in
/// `geofence-scenarios/`, **outside this repo**, because the captures still carry real
/// coordinates and real business fence names. Nothing here may become a committed fixture until
/// redaction exists.
///
/// Values are kept as `String` rather than decoded into typed fields on purpose. The tail is an
/// untyped `key=value` contract shared with an off-device parser in another language; decoding it
/// into Swift types here would invent a second schema that could drift from the one the SDK
/// actually emits, which is the failure `GeofenceLogTailTests` exists to prevent.
struct Scenario {
    let name: String
    let platform: String
    let header: Header
    let records: [Record]

    struct Header {
        let name: String
        let platform: String
        /// `regression` (the default) for a recorded drive, `conformance` for an authored scenario
        /// written against the shared vocabulary and expected to hold on every platform.
        let expect: String
        let startedAt: String
        let sdk: String?
        let device: String?
    }

    /// Whether this scenario claims to be platform-independent. A recorded drive never is: it is
    /// one OS's callback timeline, and the other OS would not have produced it.
    var isConformance: Bool { header.expect == "conformance" }

    /// One line of the scenario. `at` is seconds since the drive started — the virtual clock's only input.
    struct Record {
        enum Kind: String {
            case given
            case when
            case then
            /// Context only: neither an input nor an assertion.
            case note
        }

        let kind: Kind
        let at: TimeInterval
        let ev: String
        let fields: [String: String]

        /// The fence this record concerns.
        ///
        /// Not `ids`: on iOS that appears only on `registration.applied`, where it is the whole
        /// registered set. Android's per-callback batch needs its own accessor in an Android harness.
        var fenceId: String? { fields["id"] }

        var transition: GeofenceTransition? { fields["t"].flatMap(GeofenceTransition.init(rawValue:)) }

        /// Horizontal accuracy in metres. Present on stimuli only — the transform strips it from
        /// expectations, because it is an input no replay could reproduce as an output.
        var accuracy: String? { fields["acc"] }

        /// Why the SDK decided what it decided — `cooldown`, `no_state_change`, and so on.
        var reason: String? { fields["why"] }
    }

    /// `t0` as a `Date`, when the header carries a parseable one.
    ///
    /// Needed only to place an OS event's absolute `edate` on the scenario's own timeline. Optional
    /// because a synthetic scenario's `t0` is free text ("t" in the matcher's fixtures).
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
            expect: head["expect"] as? String ?? "regression",
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
            // `at` is required on everything the runner schedules. A record without one cannot be
            // placed on the virtual clock, and silently defaulting it to 0 would reorder the run.
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

    /// Renders a JSON value the way the tail would have carried it, so a scenario field compares
    /// equal to the emitted string. `14.0` in JSON is `14.0` in the tail; `true` is `true`.
    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if value is NSNull { return "null" }
        // `fixture.api.fetch` carries the whole fence catalogue as a nested array. `String(describing:)`
        // would render it as a Swift debug description that cannot be parsed back, so nested JSON is
        // re-serialized as JSON and stays readable by the runner.
        if value is [Any] || value is [String: Any] {
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let json = String(data: data, encoding: .utf8)
            else { return String(describing: value) }
            return json
        }
        guard let number = value as? NSNumber else { return String(describing: value) }
        // `JSONSerialization` hands back `NSNumber` for booleans and numbers alike, and NSNumber
        // bridges to *both* `Bool` and `Int` — `as? Bool` on the number 1 succeeds and yields
        // `true`. Casting in the wrong order silently rewrites every `n=1` as `n=true`. Only the
        // CoreFoundation type id distinguishes them.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        let double = number.doubleValue
        // The tail prints whole floats with one decimal (`acc=14.0`) and integers bare (`n=1`), so
        // the scenario's JSON type decides the rendering: a JSON `14.0` must not become `14`.
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
