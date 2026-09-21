@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// **The tests the feature is verified with, on a laptop.**
///
/// One funnel: load a recorded drive, install its `given`, dispatch each `when` on the virtual
/// clock, and assert the SDK's decisions still match the ones it made in the car. Adding a drive
/// adds a test — there is no per-drive code.
///
/// Everything the SDK decides is real. Only the OS region monitor and the clock are substituted,
/// so a failure here is a change in geofence behaviour, not in the scaffolding.
@Suite("Scenario replay", .serialized)
@MainActor
struct ScenarioReplayTests {
    /// The runner's stimulus list must be ordered the way the runner *delivered*, not the way the
    /// file happened to be written.
    ///
    /// `ReplayMatcher.groups` locates a decision's stimulus with `lastIndex { $0 <= record.at }`,
    /// which is only meaningful on an ascending list. Inputs go through `stableByTime`, so a
    /// capture whose lines are not already sorted was being graded against boundaries that never
    /// happened in that order. No recorded drive is out of order today, which is exactly why this
    /// case is written rather than waited for.
    ///
    /// The out-of-order pair is `identity.changed` and `app.foreground`, both stimuli. It used to
    /// be `app.background`, which no longer bounds a window — leaving it as the unsorted line
    /// would have kept this test green while asserting nothing about order.
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
    /// `device.state` and `app.background` change nothing the SDK decides — `deliverAppInput`
    /// takes both and does nothing with them. They were still splitting the fix-provider's
    /// windows and the matcher's groups, so a battery line landing inside work the previous real
    /// input started moved that work's cache read or decision into a phase the SDK never had.
    ///
    /// `app.foreground` is the control: it looks like the same class of record and is not one,
    /// because it drives the re-arm.
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

    /// A recorded pull whose position cannot be rebuilt fails the run instead of vanishing.
    ///
    /// The pull timeline dropped it and `deliverFix` returned true for the same record — a pull is
    /// not delivered, so it has nothing to refuse — and the run stayed green one recorded cache
    /// read short. `prov=none` is the one pull that legitimately carries no position: it is a read
    /// that found nothing, which is an answer.
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
            // Unreachable: the trait above skips this runtime. Recorded rather than returned
            // quietly, because a silent return is a green test that asserted nothing.
            Issue.record("replay needs iOS 17+ — the availability trait should have skipped")
            return
        }
        let scenario = try ScenarioLoader.load(path: #require(Scenarios.path(name)))

        // **The harness is built inside the binding, not before it.** `withTail` forces the
        // diagnostic tail on through a task-local, and a task inherits one only if it was created
        // inside the scope. The SDK's event consumer is started by the monitor's initialiser, so a
        // harness constructed out here leaves that one task writing untagged prose: the whole
        // registration path still matched, every OS callback silently produced nothing, and the
        // drive read as "the SDK stopped reacting" rather than "the log lost its tail".
        let (harness, result) = try await ReplayHarness.withTail { () -> (ReplayHarness, ReplayRunner.Result) in
            let harness = ReplayHarness()
            return try (harness, await ReplayRunner.run(scenario, on: harness))
        }
        // Detached after the run, so a composition nobody is reading any more stops answering the
        // bootstrap on a late reconcile or authorization change. It does not free the monitor —
        // see `detachFromBootstrap` for why that needs an SDK-side cancel — so dead monitors from
        // earlier drives still react to `enterForeground()`. Harmless to a live drive's
        // assertions, which read this harness's own logger and OS double.
        defer { harness.detachFromBootstrap() }

        // An input the harness cannot drive means the run never earned its expectations, so this is
        // checked before the match rather than after.
        #expect(
            result.unsupported.isEmpty,
            "\(name): no seam for \(result.unsupported.count) inputs — \(result.unsupported.prefix(5).joined(separator: ", "))"
        )

        // Ahead of the per-decision report: fixtures are queued up front, so a replay that syncs a
        // different number of times than the drive still gets plausible answers and diverges
        // quietly. When this fires, every mismatch below is downstream of the wrong catalogue and
        // reading them is wasted effort.
        #expect(harness.fetchAccounting() == nil, "\(name): \(harness.fetchAccounting() ?? "")")

        // Same class of check as the fetch accounting: a replay that consults a position the drive
        // never captured is guessing, and the guess surfaces later as a wrong baseline rather than
        // as an obviously missing input.
        #expect(harness.pullAccounting() == nil, "\(name): \(harness.pullAccounting() ?? "")")

        // And the same class again for the OS side. The wrapper subscribes to the event stream
        // asynchronously at init, so a crossing pushed before it attaches goes nowhere — which
        // reads downstream as the SDK ignoring a callback rather than as one never arriving.
        #expect(
            harness.conditionMonitor.deliveredWithNoSubscriber == 0,
            "\(name): \(harness.conditionMonitor.deliveredWithNoSubscriber) OS callback(s) delivered before the SDK was listening"
        )

        // Every expectation the drive recorded. There is no exclusion list: a decision replay cannot
        // reproduce is a finding about the seam, not a row to skip.
        //
        // A scenario must decide something, but the count is not a proxy for how good a drive is —
        // a stationary sign-in legitimately produces three decisions, and the guard against a
        // vacuous pass is `unsupported.isEmpty` plus the matcher's per-`ev` count check, not a
        // threshold. Whether a capture is a real drive is a human call, not one a floor can make.
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
    /// Discovery drops what it cannot parse, because a `@Test` argument list is built before any
    /// test runs and cannot throw. Without this case that drop is invisible: the suite reports a
    /// clean pass over the drives it *could* read and says nothing about the ones it could not.
    ///
    /// Enabled on `isAvailable` alone — a corpus that is present but entirely unreadable must fail
    /// here rather than skip, which is exactly the case a `replayable`-gated trait would miss.
    @Test(.enabled(if: Scenarios.isAvailable))
    func discover_givenScenarioFilesOnDisk_expectEveryOneReadable() {
        // `unreadable` is populated as a side effect of discovery, and both halves contribute, so
        // force the full list before reading it.
        _ = Scenarios.replayable
        let found = Scenarios.recorded

        // A corpus that resolves to a directory holding no drives is the failure mode this whole
        // test exists to refuse, and asserting only on `unreadable` misses it: point the override
        // one level too high — `geofence-scenarios` instead of `geofence-scenarios/recorded`, the
        // exact mistake this file's own documentation warns about — and every check below passes
        // over zero drives. `isAvailable` is true because the parent is a directory.
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
