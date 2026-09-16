@testable import CioLocationGeofence
import Foundation

/// Compares what the SDK emitted on replay against what it emitted on the road.
///
/// Two rules, and both are needed:
///
/// 1. **Ordered between stimuli, unordered within one.** Every `then` must appear, and expectations
///    triggered by *different* stimuli must appear in the recorded order. Expectations triggered by
///    the *same* stimulus may arrive in any order, because `GeofenceMonitorBinder` dispatches the
///    tracker and coordinator paths as concurrent fire-and-forget `Task`s — so whether
///    `movement.exit` or `transition.accepted` lands first is a scheduling detail, not behaviour.
///    Pinning it would make the suite flaky for a reason the SDK does not control. This is the
///    `"group": n` semantics the format specified, derived from each record's `at` rather than
///    authored into the file. Emissions the scenario does not mention are ignored, because the
///    transform deliberately drops records and a new diagnostic line should not turn a drive red.
/// 2. **Exact count per `ev`.** For each event name the scenario mentions, the number emitted must
///    match exactly. Rule 1 alone would pass an SDK that emitted *two* `transition.accepted` where
///    the drive saw one — a duplicate-delivery regression sailing through as a subsequence.
///
/// A `then` asserts **only the keys it lists**. The transform already stripped the volatile ones
/// (`ms`, `age`, `acc`), so anything still present is something the drive is entitled to pin.
enum ReplayMatcher {
    struct Mismatch: CustomStringConvertible {
        enum Kind {
            case missing(expectedIndex: Int)
            case fieldDiffers(expectedIndex: Int, key: String, expected: String, actual: String)
            case countDiffers(ev: String, expected: Int, actual: Int)
        }

        let kind: Kind

        var description: String {
            switch kind {
            case .missing(let i):
                "expectation #\(i) never arrived"
            case .fieldDiffers(let i, let key, let expected, let actual):
                "expectation #\(i): \(key) expected \(expected), got \(actual)"
            case .countDiffers(let ev, let expected, let actual):
                "\(ev): drive emitted \(expected), replay emitted \(actual)"
            }
        }
    }

    /// Both sequences side by side, for a failure message.
    ///
    /// A list of mismatches says *what* did not line up; when the cause is ordering rather than
    /// behaviour, only seeing the two sequences says *why*.
    ///
    /// **The replay column is narrowed to the event names the drive asserts.** `emitted` is the whole
    /// diagnostic tail — every `fence.cataloged`, every `location.fix` — and against a `then` list of
    /// nineteen rows that pushed the two sequences so far out of step that the columns lined up
    /// nothing at all. The comparison itself still runs over the full tail; only this rendering is
    /// filtered, so an emission the drive never mentions can still be read from the log.
    static func diff(expected: [Scenario.Record], actual: [[String: String]]) -> String {
        func label(_ ev: String, _ id: String?, _ t: String?) -> String {
            [ev, id, t].compactMap { $0 }.joined(separator: "/")
        }
        let asserted = Set(expected.map(\.ev))
        let want = expected.map { label($0.ev, $0.fenceId, $0.transition?.rawValue) }
        let got = actual
            .filter { asserted.contains($0["ev"] ?? "") }
            .map { label($0["ev"] ?? "?", $0["id"] ?? $0["ids"], $0["t"]) }
        let rows = (0 ..< max(want.count, got.count)).prefix(120).map { index -> String in
            let l = index < want.count ? want[index] : ""
            let r = index < got.count ? got[index] : ""
            return "  \(l == r ? " " : "≠") \(l.padding(toLength: 44, withPad: " ", startingAt: 0))\(r)"
        }
        return "    drive\(String(repeating: " ", count: 42))replay\n" + rows.joined(separator: "\n")
    }

    /// Groups expectations by the stimulus that triggered them: everything emitted after one
    /// `when` and before the next belongs to the same concurrent burst.
    static func grouped(_ expected: [Scenario.Record], stimuli: [TimeInterval]) -> [Int] {
        expected.map { record in stimuli.lastIndex { $0 <= record.at } ?? 0 }
    }

    static func compare(
        expected: [Scenario.Record],
        actual: [[String: String]],
        stimuli: [TimeInterval] = []
    ) -> [Mismatch] {
        var mismatches: [Mismatch] = []
        var consumed = Set<Int>()
        var cursor = 0

        // Rule 1 — one group at a time. Within a group, order is free; the cursor only advances
        // past a group once all of its expectations have been placed.
        for group in groups(expected, stimuli: stimuli) {
            var placed: [Int] = []
            for index in group {
                let want = expected[index]
                guard let hit = seek(want, in: actual, from: cursor, skipping: consumed) else {
                    mismatches.append(contentsOf: explain(want, at: index, in: actual, from: cursor))
                    continue
                }
                consumed.insert(hit)
                placed.append(hit)
            }
            cursor = (placed.max().map { $0 + 1 } ?? cursor)
        }

        // Rule 2 — counts, for the event names this drive talks about.
        for ev in Set(expected.map(\.ev)).sorted() {
            let want = expected.count { $0.ev == ev }
            let got = actual.count { $0["ev"] == ev }
            if want != got {
                mismatches.append(.init(kind: .countDiffers(ev: ev, expected: want, actual: got)))
            }
        }

        return mismatches
    }

    /// Expectation indices grouped by the stimulus that triggered them.
    private static func groups(_ expected: [Scenario.Record], stimuli: [TimeInterval]) -> [[Int]] {
        guard !stimuli.isEmpty else { return expected.indices.map { [$0] } }
        var byStimulus: [Int: [Int]] = [:]
        for (index, record) in expected.enumerated() {
            let stimulus = stimuli.lastIndex { $0 <= record.at } ?? 0
            byStimulus[stimulus, default: []].append(index)
        }
        return byStimulus.keys.sorted().map { byStimulus[$0]! }
    }

    /// Why an expectation did not match: the closest same-`ev` emission, field by field.
    private static func explain(
        _ want: Scenario.Record,
        at index: Int,
        in actual: [[String: String]],
        from cursor: Int
    ) -> [Mismatch] {
        var found: [Mismatch] = [.init(kind: .missing(expectedIndex: index))]
        guard cursor < actual.count,
              let near = actual[cursor...].first(where: { $0["ev"] == want.ev })
        else { return found }
        for (key, value) in want.fields.sorted(by: { $0.key < $1.key }) where near[key] != value {
            found.append(.init(kind: .fieldDiffers(
                expectedIndex: index, key: key, expected: value, actual: near[key] ?? "<absent>"
            )))
        }
        return found
    }

    /// First unconsumed emission at or after `start` that satisfies `want`.
    ///
    /// Consumed indices are skipped so two identical expectations cannot both match one emission —
    /// which would hide a dropped duplicate.
    private static func seek(
        _ want: Scenario.Record,
        in actual: [[String: String]],
        from start: Int,
        skipping consumed: Set<Int>
    ) -> Int? {
        guard start < actual.count else { return nil }
        for index in start ..< actual.count where !consumed.contains(index) {
            let record = actual[index]
            guard record["ev"] == want.ev else { continue }
            if want.fields.allSatisfy({ record[$0.key] == $0.value }) { return index }
        }
        return nil
    }
}
