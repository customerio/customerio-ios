import Foundation

/// Private corpus outside this repo (real coordinates). `CIO_GEOFENCE_SCENARIOS` must point at
/// `mobile-replay-harness/scenarios`; under `xcodebuild` prefix it `TEST_RUNNER_` or it's ignored.
/// Gate tests with `.enabled(if: isAvailable)`: an early return reports passed.
enum Scenarios {
    private static let platform = "ios"

    private static let any = "any"

    private static let kinds: Set<String> = ["recorded", "authored"]

    static let root: URL? = {
        if let override = ProcessInfo.processInfo.environment["CIO_GEOFENCE_SCENARIOS"] {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        // From this file, not the working directory, which differs between `xcodebuild` and
        // `swift test`.
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

    /// Discovery feeds a `@Test` argument list and can't throw, so failures are collected here and
    /// reported by a case that runs.
    private(set) static var unreadable: [String] = []

    /// An unknown platform is a broken file, reported rather than skipped.
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

    static let replayable: [String] = discovered.map(\.name)

    /// Separate: authored files alone would satisfy a "found any drives?" guard.
    static let recorded: [String] = discovered.filter(\.scenario.isRecorded).map(\.name)
}
