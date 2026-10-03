@testable import CioLocationGeofence
import Foundation

/// Ordered across stimuli, unordered within one (the binder dispatches each callback on its own
/// `Task`); unmentioned emissions are ignored. Per-`ev` counts must match exactly, or a duplicate
/// passes as a subsequence. A `then` asserts only the keys it lists.
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

    /// Only this rendering is narrowed to asserted events, not the comparison.
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

        // The cursor passes a group only once all of it is placed.
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

        for ev in Set(expected.map(\.ev)).sorted() {
            let want = expected.count { $0.ev == ev }
            let got = actual.count { $0["ev"] == ev }
            if want != got {
                mismatches.append(.init(kind: .countDiffers(ev: ev, expected: want, actual: got)))
            }
        }

        return mismatches
    }

    private static func groups(_ expected: [Scenario.Record], stimuli: [TimeInterval]) -> [[Int]] {
        guard !stimuli.isEmpty else { return expected.indices.map { [$0] } }
        var byStimulus: [Int: [Int]] = [:]
        for (index, record) in expected.enumerated() {
            let stimulus = stimuli.lastIndex { $0 <= record.at } ?? 0
            byStimulus[stimulus, default: []].append(index)
        }
        return byStimulus.keys.sorted().map { byStimulus[$0]! }
    }

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

    /// Skips consumed indices so two identical expectations can't both match one emission.
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
