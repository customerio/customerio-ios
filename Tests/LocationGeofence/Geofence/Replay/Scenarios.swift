import Foundation

/// The scenario corpus, which lives outside this repo.
///
/// `mobile-replay-harness/` is a separate private checkout — the captures carry real coordinates
/// and real business fence names. Leave it beside this repo, or point `CIO_GEOFENCE_SCENARIOS` at
/// the directory that holds the `.scenario.ndjson` files — that is `mobile-replay-harness/scenarios`,
/// not `mobile-replay-harness`. The sibling fallback appends `scenarios` for you; the override does
/// not, and pointing it one level too high finds nothing and reports the whole suite as skipped.
///
/// One flat directory. A scenario declares where it runs in its own header, so there is nothing to
/// sort by hand and no second directory whose absence changes what gets graded.
///
/// **Under `xcodebuild`, prefix the variable with `TEST_RUNNER_`.** Simulator tests do not inherit
/// the shell environment; only variables with that prefix are forwarded to the test process. A bare
/// `CIO_GEOFENCE_SCENARIOS=… xcodebuild …` is silently ignored and the sibling checkout is used
/// instead — which looks exactly like the override working, because the tests still run and still
/// pass. It cost a bogus isolation check and a negative control that appeared to prove the matcher
/// was asserting nothing.
///
///     TEST_RUNNER_CIO_GEOFENCE_SCENARIOS=/path/to/mobile-replay-harness/scenarios xcodebuild … test
///
/// Tests that need it are gated on `isAvailable` with `.enabled(if:)` so they report as **skipped**
/// when absent. Returning early instead reports as *passed* — green tests that asserted nothing.
enum Scenarios {
    /// This composition. A scenario runs here if its header names this, or names every platform.
    private static let platform = "ios"

    /// A scenario that declares this runs on every composition, not just the one that recorded it.
    private static let any = "any"

    /// The provenance values a header may declare. Anything else is a broken file, not a default.
    private static let kinds: Set<String> = ["recorded", "authored"]

    static let root: URL? = {
        if let override = ProcessInfo.processInfo.environment["CIO_GEOFENCE_SCENARIOS"] {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        // Resolved from this file rather than the working directory, which differs between
        // `xcodebuild` and a bare `swift test`.
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 {
            dir.deleteLastPathComponent()
        }
        let sibling = dir.appendingPathComponent("mobile-replay-harness/scenarios")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }()

    static var isAvailable: Bool { root != nil }

    static func path(_ name: String) -> String? {
        guard let root else { return nil }
        let candidate = root.appendingPathComponent("\(name).scenario.ndjson")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    /// Scenario files present on disk that this harness could not read, or that named a platform
    /// it does not recognise.
    ///
    /// Discovery cannot throw — it feeds a `@Test` argument list, which is built before any test
    /// runs — so an unreadable drive can only be *collected* here and reported by a case that does
    /// run. Silently dropping it, which is what a bare `try?` does, lets the suite go green having
    /// replayed fewer drives than exist: the precise failure this harness is built to refuse.
    private(set) static var unreadable: [String] = []

    /// Every scenario in the corpus whose header says it belongs on this composition, paired with
    /// the parsed scenario so a caller can filter further without re-reading the file.
    ///
    /// A header naming neither this platform, the other one, nor `any` is a broken file rather
    /// than somebody else's drive, so it is reported rather than quietly skipped. Only a *load*
    /// failure was recorded before, which left a misspelled `"platfrom"` key — or a stray `"iOS"`
    /// — parsing cleanly, defaulting to `unknown`, and vanishing from the run with nothing said.
    private static let discovered: [(name: String, scenario: Scenario)] = {
        guard let root else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files
            .filter { $0.hasSuffix(".scenario.ndjson") }
            .map { String($0.dropLast(".scenario.ndjson".count)) }
            .sorted()
            .compactMap { name -> (String, Scenario)? in
                guard let path = path(name) else {
                    unreadable.append(name)
                    return nil
                }
                do {
                    return try (name, ScenarioLoader.load(path: path))
                } catch {
                    unreadable.append("\(name): \(error)")
                    return nil
                }
            }
            .filter { name, scenario in
                guard [platform, "android", any].contains(scenario.platform) else {
                    unreadable.append(
                        "\(name): header platform is \"\(scenario.platform)\", "
                            + "expected \"ios\", \"android\" or \"any\""
                    )
                    return false
                }
                // Validated, not defaulted, for the same reason as `platform`: defaulting a
                // missing `source.kind` to `recorded` let an authored scenario with no `source`
                // satisfy the "did discovery find any drives?" guard on its own.
                guard kinds.contains(scenario.header.sourceKind) else {
                    unreadable.append(
                        "\(name): header source.kind is \"\(scenario.header.sourceKind)\", "
                            + "expected \"recorded\" or \"authored\""
                    )
                    return false
                }
                return scenario.platform == platform || scenario.platform == any
            }
    }()

    /// Everything a run grades: recorded drives and authored scenarios alike.
    static let replayable: [String] = discovered.map(\.name)

    /// The recorded drives alone, without the authored scenarios.
    ///
    /// Separate from `replayable` because the two answer different questions. A guard asking "did
    /// discovery find anything" against the combined list is satisfied by the authored files, which
    /// carry no device and cannot detect a corpus path that resolved somewhere drive-less.
    static let recorded: [String] = discovered.filter(\.scenario.isRecorded).map(\.name)
}
