@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// Loads each recorded drive, installs its `given`, dispatches each `when` on the virtual clock,
/// and asserts the SDK's decisions still match the ones it made in the car. Adding a drive adds a
/// test — there is no per-drive code.
///
/// Everything the SDK decides is real; only the OS, the network and the clock are substituted
/// (see `ReplayHarness`), so a failure here is a change in geofence behaviour.
@Suite("Scenario replay", .serialized)
@MainActor
struct ScenarioReplayTests {
    /// Provenance must not default to `recorded`: an authored scenario without `source` would then
    /// satisfy the "did discovery find any drives?" guard on its own, over zero real drives.
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

    /// The runner's stimulus list must be ordered the way the runner *delivered*, not the way the
    /// file happened to be written: `ReplayMatcher.groups` finds a decision's stimulus with
    /// `lastIndex { $0 <= record.at }`, which needs an ascending list.
    ///
    /// The out-of-order pair is `identity.changed` and `app.foreground`, both stimuli.
    /// `app.background` does not bound a window, so it cannot be the unsorted line.
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

    /// A record the runner accepts as a no-op must not bound a window.
    ///
    /// `device.state` and `app.background` change nothing the SDK decides. Letting one split the
    /// fix-provider's windows or the matcher's groups would move the previous input's cache read or
    /// decision into a phase the SDK never had.
    ///
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

        // Still delivered — they are accepted inputs, just inert ones.
        #expect(result.unsupported.isEmpty, "unsupported: \(result.unsupported)")
        #expect(result.stimuli == [0.0, 3.0], "inert records bounded a window: \(result.stimuli)")
    }

    /// A recorded pull whose position cannot be rebuilt fails the run instead of vanishing and
    /// leaving the run one recorded cache read short. `prov=none` is the one pull that legitimately
    /// carries no position: a read that found nothing.
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

    /// The read a callback carries fails closed on the same shapes a standalone pull does.
    ///
    /// It can be the only answer the provider has for the callback's window, so treating an
    /// incomplete one as an empty pull would hand the SDK a nil the drive never recorded while
    /// `unsupported` and the pull accounting both stayed clean.
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

        // The callback itself is deliverable, so the only finding is its read; `fixsrc` in the
        // tag says which of the two failed.
        #expect(
            result.unsupported == ["when os.callback@1.0 fixsrc=manager_cache"],
            "a callback-carried read that lost its position was not reported: \(result.unsupported)"
        )
    }

    /// `fixsrc=none` stays legal here too, so the check above cannot be satisfied by rejecting
    /// every callback that carries no position.
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

    /// The empty read stays legal, so the check above cannot be satisfied by rejecting every
    /// position-less pull.
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
            // Unreachable: the trait above skips this runtime. Recorded, not returned quietly,
            // so it cannot pass having asserted nothing.
            Issue.record("replay needs iOS 17+ — the availability trait should have skipped")
            return
        }
        let scenario = try ScenarioLoader.load(path: #require(Scenarios.path(name)))

        // The harness is built inside `withTail`, not before it: the tail is a task-local, and the
        // monitor's event consumer task is started by its initialiser. Built outside, that task
        // logs untagged prose and every OS callback appears to produce nothing.
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        // Stops a finished composition answering the bootstrap. It does not free the monitor; see
        // `detachFromBootstrap`.
        defer { harness.detachFromBootstrap() }

        // An input the harness cannot drive means the run never earned its expectations.
        #expect(
            result.unsupported.isEmpty,
            "\(name): no seam for \(result.unsupported.count) inputs — \(result.unsupported.prefix(5).joined(separator: ", "))"
        )

        // Fixtures are queued up front, so a replay that syncs a different number of times still
        // gets plausible answers. When this fires, every mismatch below is downstream of it.
        #expect(harness.fetchAccounting() == nil, "\(name): \(harness.fetchAccounting() ?? "")")

        // A replay that reads a position the drive never captured is guessing, and the guess
        // surfaces later as a wrong baseline rather than as a missing input.
        #expect(harness.pullAccounting() == nil, "\(name): \(harness.pullAccounting() ?? "")")

        // The wrapper subscribes to the event stream asynchronously at init, so a crossing pushed
        // before it attaches goes nowhere and reads as the SDK ignoring a callback.
        #expect(
            harness.conditionMonitor.deliveredWithNoSubscriber == 0,
            "\(name): \(harness.conditionMonitor.deliveredWithNoSubscriber) OS callback(s) delivered before the SDK was listening"
        )

        // The same guard for visits: one pushed with no handler bound reaches nothing.
        #expect(
            harness.visitMonitor.deliveredWithNoSubscriber == 0,
            "\(name): \(harness.visitMonitor.deliveredWithNoSubscriber) visit(s) delivered before the SDK was listening"
        )

        // No exclusion list: a decision replay cannot reproduce is a finding about the seam.
        //
        // Non-empty, not a threshold: a stationary sign-in legitimately produces three decisions.
        // The guard against a vacuous pass is `unsupported.isEmpty` plus the per-`ev` count check.
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

    /// Every scenario file on disk was readable.
    ///
    /// Discovery drops what it cannot parse (a `@Test` argument list cannot throw), so without this
    /// case the suite passes over the drives it could read and says nothing about the rest.
    ///
    /// Enabled on `isAvailable` alone, so a corpus that is present but entirely unreadable fails
    /// here rather than skipping.
    @Test(.enabled(if: Scenarios.isAvailable))
    func discover_givenScenarioFilesOnDisk_expectEveryOneReadable() {
        // `unreadable` is populated as a side effect of discovery, so force it before reading.
        _ = Scenarios.replayable
        let found = Scenarios.recorded

        // Asserting only on `unreadable` misses a corpus path that resolves to a directory with no
        // drives: point the override at `mobile-replay-harness` instead of
        // `mobile-replay-harness/scenarios` and `isAvailable` is still true.
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
