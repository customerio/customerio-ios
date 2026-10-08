@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("Scenario replay", .serialized)
@MainActor
struct ScenarioReplayTests {
    @Test
    func load_givenHeaderWithoutSource_expectUnknownProvenance() throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"no-source","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        """)

        #expect(scenario.header.sourceKind == "unknown")
        #expect(scenario.isRecorded == false)
    }

    @Test
    func load_givenAuthoredSource_expectNotCountedAsADrive() throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"authored","platform":"any","t0":"t","source":{"kind":"authored"}}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        """)

        #expect(scenario.isRecorded == false)
    }

    @Test
    func load_givenRecordedSource_expectCountedAsADrive() throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"recorded","platform":"ios","t0":"t","source":{"kind":"recorded"}}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        """)

        #expect(scenario.isRecorded)
    }

    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_whenRequestedResponseFollowsLastStimulus_thenDeadlineUsesResponseWithoutExpectedOutputs() async throws {
        let body = """
        [{"id":"A","name":"F","latitude":10,"longitude":20,"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"],"dwellThresholdSeconds":60}]
        """
        let encodedBody = try #require(String(data: JSONSerialization.data(withJSONObject: body, options: .fragmentsAllowed), encoding: .utf8))
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"tail-response","platform":"ios","t0":"t","source":{"kind":"authored"}}
        {"k":"given","at":2.1,"ev":"fixture.api.fetch","ok":true,"body":\(encodedBody)}
        {"k":"when","at":0,"ev":"process.start","session":1}
        {"k":"when","at":0.1,"ev":"module.init"}
        {"k":"when","at":1,"ev":"identity.changed","ok":true}
        {"k":"when","at":2,"ev":"location.fix","prov":"bus","lat":10.0151,"lon":20}
        {"k":"when","at":2.01,"ev":"location.fix","prov":"manager_cache","lat":10.0151,"lon":20,"acc":10,"age":0}
        {"k":"when","at":30,"ev":"os.callback","id":"A","t":"enter","fixsrc":"manager_cache","lat":10,"lon":20,"acc":10,"age":0}
        {"k":"note","at":90.6,"ev":"fix.received","prov":"movement_resolver","lat":10,"lon":20,"acc":10,"age":0.32}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap()
            harness.dwellScheduler.cancelAll()
        }
        #expect(result.unsupported.isEmpty)
        #expect(scenario.then.isEmpty, "expected decisions must not be needed to pace responses")
        let dwells = harness.deliveredMetrics.filter { $0.transition == .dwell }
        #expect(dwells.count == 1)
        #expect(try abs(#require(dwells.first).timestamp.timeIntervalSince(harness.epoch) - 90.28) < 0.001)
        #expect(harness.now == harness.epoch.addingTimeInterval(90.6))
    }

    /// The out-of-order pair is `identity.changed` and `app.foreground`; `app.background` bounds no
    /// window.
    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenScenarioLinesOutOfOrder_expectStimuliAscending() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"out-of-order","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":3.0,"ev":"app.background"}
        {"k":"when","at":2.0,"ev":"identity.changed","ok":true}
        {"k":"when","at":1.0,"ev":"app.foreground"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(result.unsupported.isEmpty, "unsupported: \(result.unsupported)")
        #expect(result.stimuli == result.stimuli.sorted(), "stimuli not ascending: \(result.stimuli)")
        #expect(result.stimuli == [0.0, 1.0, 2.0])
    }

    /// `app.foreground` is the control: it looks inert but drives the re-arm.
    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenInertRecords_expectNoStimulusBoundary() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"inert","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":1.0,"ev":"device.state","battery":"0.5"}
        {"k":"when","at":2.0,"ev":"app.background"}
        {"k":"when","at":3.0,"ev":"app.foreground"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(result.unsupported.isEmpty, "unsupported: \(result.unsupported)")
        #expect(result.stimuli == [0.0, 3.0], "inert records bounded a window: \(result.stimuli)")
    }

    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenPullMissingPosition_expectReportedUnsupported() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"malformed-pull","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":1.0,"ev":"location.fix","prov":"manager_cache"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(
            result.unsupported == ["when location.fix@1.0"],
            "a pull that lost its position was not reported: \(result.unsupported)"
        )
    }

    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenCallbackCarriedReadMissingPosition_expectReportedUnsupported() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"carried-incomplete","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":1.0,"ev":"os.callback","id":"A","t":"enter","fixsrc":"manager_cache"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(
            result.unsupported == ["when os.callback@1.0 fixsrc=manager_cache"],
            "a callback-carried read that lost its position was not reported: \(result.unsupported)"
        )
    }

    /// Control for the test above: it can't pass by rejecting every position-less callback.
    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenCallbackCarriedReadThatFoundNothing_expectAccepted() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"carried-empty","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":1.0,"ev":"os.callback","id":"A","t":"enter","fixsrc":"none"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(result.unsupported.isEmpty, "unsupported: \(result.unsupported)")
    }

    /// Control for the pull test: it can't pass by rejecting every position-less pull.
    @Test(.enabled(if: ReplayRuntime.isMonitorAvailable))
    @available(iOS 17.0, *)
    func run_givenPullThatFoundNothing_expectAccepted() async throws {
        let scenario = try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"empty-pull","platform":"ios","t0":"t"}
        {"k":"when","at":0.0,"ev":"process.start","session":1}
        {"k":"when","at":1.0,"ev":"location.fix","prov":"none"}
        """)
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(result.unsupported.isEmpty, "unsupported: \(result.unsupported)")
    }

    @Test(
        .enabled(if: Scenarios.isAvailable && ReplayRuntime.isMonitorAvailable),
        arguments: Scenarios.replayable
    )
    func replay_givenRecordedDrive_expectRecordedDecisions(_ name: String) async throws {
        guard #available(iOS 17.0, *) else {
            // Recorded, not a quiet return, so it can't pass having asserted nothing.
            Issue.record("replay needs iOS 17+ — the availability trait should have skipped")
            return
        }
        let scenario = try ScenarioLoader.load(path: #require(Scenarios.path(name)))

        // Built inside `withTail`: the monitor's consumer task starts in init and must inherit the
        // tail.
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        defer { harness.detachFromBootstrap() }

        #expect(
            result.unsupported.isEmpty,
            "\(name): no seam for \(result.unsupported.count) inputs — \(result.unsupported.prefix(5).joined(separator: ", "))"
        )

        // When this fires, every mismatch below is downstream of it.
        #expect(harness.fetchAccounting() == nil, "\(name): \(harness.fetchAccounting() ?? "")")

        #expect(harness.pullAccounting() == nil, "\(name): \(harness.pullAccounting() ?? "")")

        #expect(
            harness.conditionMonitor.deliveredWithNoSubscriber == 0,
            "\(name): \(harness.conditionMonitor.deliveredWithNoSubscriber) OS callback(s) delivered before the SDK was listening"
        )

        #expect(
            harness.visitMonitor.deliveredWithNoSubscriber == 0,
            "\(name): \(harness.visitMonitor.deliveredWithNoSubscriber) visit(s) delivered before the SDK was listening"
        )

        // No exclusion list: a decision replay can't reproduce is a finding about the seam. Non-empty,
        // not a threshold: a stationary sign-in legitimately produces three decisions.
        let expected = scenario.then
        #expect(!expected.isEmpty, "\(name): the drive recorded no decisions at all")

        let mismatches = ReplayMatcher.compare(
            expected: expected,
            actual: result.emitted,
            stimuli: result.stimuli
        )
        #expect(
            mismatches.isEmpty,
            """
            \(name): \(mismatches.count) mismatch(es) against \(expected.count) recorded decisions
            \(mismatches.prefix(8).map { "  • \($0)" }.joined(separator: "\n"))

            \(ReplayMatcher.diff(expected: expected, actual: result.emitted))
            """
        )
    }

    /// Enabled on `isAvailable` alone, so an entirely unreadable corpus fails rather than skips.
    @Test(.enabled(if: Scenarios.isAvailable))
    func discover_givenScenarioFilesOnDisk_expectEveryOneReadable() {
        // Forces discovery, which populates `unreadable`.
        _ = Scenarios.replayable
        let found = Scenarios.recorded

        // `unreadable` alone misses a path one level too high, where `isAvailable` is still true.
        #expect(
            !found.isEmpty,
            "the corpus at \(Scenarios.root?.path ?? "?") holds no recorded drive — check the path points at the directory containing the .scenario.ndjson files. Asserted on recorded drives alone: the authored conformance scenarios resolve from a sibling directory, so they would satisfy this guard while zero drives were graded."
        )
        #expect(
            Scenarios.unreadable.isEmpty,
            """
            \(Scenarios.unreadable.count) scenario file(s) could not be read and were dropped from the run:
            \(Scenarios.unreadable.map { "  • \($0)" }.joined(separator: "\n"))
            """
        )
    }
}
