import Foundation

/// The recorded drives, which live outside this repo.
///
/// `geofence-scenarios/` is a separate private checkout — the captures carry real coordinates and
/// real business fence names. Leave it beside this repo, or point `CIO_GEOFENCE_SCENARIOS` at the
/// directory that holds the `.scenario.ndjson` files — that is `geofence-scenarios/recorded`, not
/// `geofence-scenarios`. The sibling fallback appends `recorded` for you; the override does not,
/// and pointing it one level too high finds no drives and reports the whole suite as skipped.
///
/// **Under `xcodebuild`, prefix the variable with `TEST_RUNNER_`.** Simulator tests do not inherit
/// the shell environment; only variables with that prefix are forwarded to the test process. A bare
/// `CIO_GEOFENCE_SCENARIOS=… xcodebuild …` is silently ignored and the sibling checkout is used
/// instead — which looks exactly like the override working, because the tests still run and still
/// pass. It cost a bogus isolation check and a negative control that appeared to prove the matcher
/// was asserting nothing.
///
///     TEST_RUNNER_CIO_GEOFENCE_SCENARIOS=/path/to/geofence-scenarios/recorded xcodebuild … test
///
/// Tests that need it are gated on `isAvailable` with `.enabled(if:)` so they report as **skipped**
/// when absent. Returning early instead reports as *passed* — green tests that asserted nothing.
enum Scenarios {
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
        let sibling = dir.appendingPathComponent("geofence-scenarios/recorded")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }()

    static var isAvailable: Bool { root != nil }

    /// Authored scenarios, beside `recorded/` rather than in it.
    ///
    /// EXPERIMENTAL. A recorded drive belongs to the OS that produced it — the same crossing fired
    /// nine minutes apart across the 2026-09-11 fleet — so a shared file can only ever be one
    /// somebody wrote. These are written against the vocabulary both platforms already share and
    /// run on both, unfiltered by the header's `platform`.
    static let conformanceRoot: URL? = {
        guard let root else { return nil }
        let sibling = root.deletingLastPathComponent().appendingPathComponent("conformance")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }()

    static func path(_ name: String) -> String? {
        for directory in [root, conformanceRoot].compactMap({ $0 }) {
            let candidate = directory.appendingPathComponent("\(name).scenario.ndjson")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }

    /// The authored scenarios, which carry no platform of their own.
    ///
    /// `expect` is checked rather than the directory: a file that has not opted in stays out, so
    /// dropping a recorded drive in here by mistake cannot silently run against the wrong OS.
    static let conformance: [String] = {
        guard let directory = conformanceRoot else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files
            .filter { $0.hasSuffix(".scenario.ndjson") }
            .map { String($0.dropLast(".scenario.ndjson".count)) }
            .filter { name in
                guard let path = path(name) else {
                    unreadable.append(name)
                    return false
                }
                do {
                    return try ScenarioLoader.load(path: path).isConformance
                } catch {
                    unreadable.append("\(name): \(error)")
                    return false
                }
            }
            .sorted()
    }()

    /// Scenario files present on disk that this harness could not read.
    ///
    /// Discovery cannot throw — it feeds a `@Test` argument list, which is built before any test
    /// runs — so an unreadable drive can only be *collected* here and reported by a case that does
    /// run. Silently dropping it, which is what a bare `try?` does, lets the suite go green having
    /// replayed fewer drives than exist: the precise failure this harness is built to refuse.
    private(set) static var unreadable: [String] = []

    /// Every drive this harness can replay, discovered from disk.
    ///
    /// Enumerated rather than listed so adding a drive is dropping in a file.
    /// The recorded drives alone, without the authored conformance scenarios.
    ///
    /// Separate from `replayable` because the two answer different questions. A guard asking "did
    /// discovery find anything" against the combined list is satisfied by the two authored files,
    /// which resolve from `root.parent/conformance` — so an override pointing at any drive-less
    /// sibling of `recorded/` still looks healthy while grading zero drives.
    static let recorded: [String] = {
        guard let root else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files
            .filter { $0.hasSuffix(".scenario.ndjson") }
            .map { String($0.dropLast(".scenario.ndjson".count)) }
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
            // The platform filter reads each header rather than trusting the filename: this harness
            // is the iOS composition, and Android batches several fences onto one callback.
            //
            // A header naming neither platform is a broken file, not somebody else's drive, so it
            // is reported rather than filtered away. Only a *load* failure was recorded before,
            // which left a misspelled `"platfrom"` key — or a stray `"iOS"` — parsing cleanly,
            // defaulting to `unknown`, and vanishing from the run with nothing said.
            .filter { name, scenario in
                guard ["ios", "android"].contains(scenario.platform) else {
                    unreadable.append("\(name): header platform is \"\(scenario.platform)\", expected \"ios\" or \"android\"")
                    return false
                }
                return scenario.platform == "ios"
            }
            .map(\.0)
            .sorted()
    }()

    /// Everything a run grades: the recorded drives plus the authored scenarios.
    static let replayable: [String] = recorded + conformance
}
