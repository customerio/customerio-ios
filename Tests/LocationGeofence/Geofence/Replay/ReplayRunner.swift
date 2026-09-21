@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

/// Walks one drive against one harness: apply each record in recorded order on the virtual clock,
/// from the first line to the last.
///
/// **Inputs only.** A `given` is something that reached the SDK from outside it — a network
/// response, a process start. Nothing here writes SDK state directly: if feeding the recorded
/// inputs does not put the SDK where the drive had it, that is the finding, not something to
/// paper over.
///
/// **Unsupported records fail the run — they are never skipped.** Quietly ignoring one would still
/// produce a green match against expectations the run never earned.
@available(iOS 17.0, *)
@MainActor
enum ReplayRunner {
    struct Result {
        /// Every parseable tail the SDK emitted, in order.
        let emitted: [[String: String]]
        /// Records the harness has no seam for, as `kind ev@at`.
        let unsupported: [String]
        /// When each input was delivered, in virtual seconds. Pulls are not inputs and are absent,
        /// so a matcher grouping expectations by "the input that preceded this" gets the same
        /// boundaries the runner actually drove — not one per cache read the SDK happened to make.
        let stimuli: [TimeInterval]
    }

    static func run(_ scenario: Scenario, on harness: ReplayHarness) async throws -> Result {
        var unsupported: [String] = []
        var seen: Set<String> = []

        // Pulled fixes go in before the first stimulus, as a timeline the provider reads from.
        //
        // `location.fix` records for `manager_cache` and `gate` are the SDK *reading* the OS cache,
        // and the record is written at the read — which happens inside work an earlier stimulus
        // started. The registration ledger reads the cache mid-sync, so delivered in sequence the
        // value would arrive after the decision it determined. See `ReplayFixProvider`.
        let pulled = scenario.when.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "location.fix",
                  let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:)),
                  !source.isArrival, source != .bus
            else { return nil }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else {
                // `prov=none` is a read that found nothing — a recorded answer, not a missing
                // record — so it is the one source that legitimately carries no position.
                if source == .none { return harness.emptyPull(at: record.at) }
                // Every other pull is a read the drive recorded an answer for, and that answer
                // cannot be rebuilt. Dropping it left the provider one read short while
                // `deliverFix` returned true for the same record further down — a pull is not
                // delivered, so it has nothing to refuse — and the run went green having lost a
                // recorded input. Reported here because this is where the loss happens:
                // `deliverFix` never sees the missing fields.
                unsupported.append("\(record.kind) \(record.ev)@\(record.at)")
                return nil
            }
            return harness.pulledFix(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                // How stale the position already was. The only part of the record the SDK reasons
                // about — `at` decides which window answers, never what the answer says.
                age: record.fields["age"].flatMap(Double.init) ?? 0,
                at: record.at
            )
        }
        // The stimuli that actually drive work — see `isStimulus` for what is left out and why.
        //
        // Ordered the same way they are *delivered*. `ReplayMatcher.groups` finds a decision's
        // stimulus with `lastIndex { $0 <= record.at }`, which assumes the list ascends; handing it
        // raw file order while the runner drove `stableByTime` meant a capture whose lines were not
        // already sorted would be graded against boundaries that never happened in that order.
        let stimuli = Self.stableByTime(scenario.when)
            .filter(Self.isStimulus)
            .map(\.at)
        harness.loadPulledFixes(
            stimuli: stimuli,
            samples: pulled,
            carried: carriedReads(scenario, on: harness)
        )

        // When the network answered, taken from the drive rather than modelled:
        // `fixture.api.fetch` is stamped on arrival, so its `at` is exactly the release time.
        harness.loadBoundaryAnswers(
            fetch: scenario.given.filter { $0.ev == "fixture.api.fetch" }.map(\.at).sorted()
        )

        // Every fixture goes in before the first stimulus, in recorded order.
        //
        // `api.fetch.result` is stamped when the response *arrives*, so a fixture always sits one
        // round-trip later in the capture than the fetch that asked for it. Installing it at that
        // timestamp is guaranteed to be late: the SDK has already asked. Queueing up front and
        // serving in order is the only placement that can be right, and `fetchAccounting()` catches
        // a replay that then syncs a different number of times.
        for record in Self.stableByTime(scenario.given) where !install(record, on: harness) {
            unsupported.append("\(record.kind) \(record.ev)@\(record.at)")
        }

        for record in Self.stableByTime(scenario.when) {
            // Runs the clock up to this input, answering on the way every boundary that answered
            // before it did — see `ReplayBoundaryGate`. What the SDK has finished by the time the
            // input lands is therefore decided by the recording, not by the harness.
            await harness.advance(to: record.at) { await settle(harness) }
            let isFirst = seen.insert(record.ev).inserted
            let handled = deliver(record, on: harness, isFirst: isFirst, scenarioEpoch: scenario.startedAt)
            if !handled { unsupported.append("\(record.kind) \(record.ev)@\(record.at)") }
            await settle(harness)
        }

        // The recording stops but the SDK does not: a capture can end with a sync in flight. Let
        // the outstanding boundaries answer so those decisions are graded rather than lost.
        try await harness.settleBoundaries()
        return Result(emitted: harness.emitted, unsupported: unsupported, stimuli: stimuli)
    }

    /// What each OS callback recorded about the fix it read to write its own line.
    ///
    /// `logReceivedCallback` reads the cache and *then* logs, so a callback record and the
    /// `location.fix` line for its own read are written microseconds apart — and a capture that
    /// stamps to the millisecond can put them on either side of a tick. The provider uses these
    /// only for a window the recorded reads left empty; see `ReplayFixProvider`.
    private static func carriedReads(_ scenario: Scenario, on harness: ReplayHarness) -> [ReplayFixProvider.CachedRead] {
        scenario.when.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "os.callback", record.fields["fixsrc"] != nil else { return nil }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else { return harness.emptyPull(at: record.at) }
            return harness.pulledFix(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                age: record.fields["age"].flatMap(Double.init) ?? 0,
                at: record.at
            )
        }
    }

    /// Cancellation is swallowed here and nowhere else: a runner walking a drive should stop
    /// pacing when the test task is cancelled, not abort the drive mid-record and report the
    /// remaining expectations as missing.
    private static func settle(_ harness: ReplayHarness) async {
        try? await ReplayHarness.letAsyncWorkRun()
    }

    /// Whether a record drove SDK work, and so bounds a window.
    ///
    /// A boundary is load-bearing twice over: `ReplayFixProvider` serves each recorded read from
    /// the window its stimulus opened, and `ReplayMatcher.groups` attributes each decision to the
    /// stimulus before it. A boundary the SDK never had splits one phase in two, which can move a
    /// cache read or a decision into a phase the drive never ran.
    ///
    /// Two kinds of `when` record are in the file without driving anything:
    ///
    /// - A **pull** is the SDK *reading* the cache, inside work an earlier stimulus started. It is
    ///   loaded into the provider's timeline instead, and letting it bound a window would fragment
    ///   the very window it belongs inside.
    /// - **`device.state` and `app.background`** have no behavioural seam on iOS at all:
    ///   `deliverAppInput` accepts both as deliberate no-ops. A battery or background line landing
    ///   inside work the previous real input started was still splitting that work's window.
    ///   `app.foreground` is *not* inert and stays — it drives `rearmOnForegroundIfStale`.
    private static func isStimulus(_ record: Scenario.Record) -> Bool {
        switch record.ev {
        case "device.state", "app.background":
            false
        case "location.fix":
            // An unreadable `prov` is not silently treated as a pull: it stays a boundary here and
            // `deliverFix` reports it as unsupported, so the run fails rather than regrouping.
            record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))?.isArrival ?? true
        default:
            true
        }
    }

    /// Records in time order, ties broken by the order the capture wrote them.
    ///
    /// `sorted(by:)` is NOT stable in Swift, and a capture is full of ties: the 2026-09-12 drive
    /// shares a timestamp between two or more records **63 times**, four deep at the worst, because
    /// the sink stamps to the millisecond and CoreLocation delivers in bursts. Sorting on `at` alone
    /// therefore let the runner reorder a burst freely — and differently from run to run, so the
    /// symptom was a wrong decision that need not reproduce.
    ///
    /// The file's order is the observed order, so it is the tiebreak.
    private static func stableByTime(_ records: [Scenario.Record]) -> [Scenario.Record] {
        records.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    // MARK: - given

    private static func install(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        switch record.ev {
        case "fixture.api.fetch":
            // A failed fetch is an input too — the drive lost the network mid-route and the SDK had
            // to carry on with what it had cached. Stubbing the failure is the point, not a fallback.
            guard record.fields["ok"] == "true" else {
                harness.enqueueFetchFailure(why: record.reason)
                return true
            }
            guard let body = record.fields["body"], body != "null",
                  (try? harness.enqueueFetch(bodyJSON: body)) != nil else { return false }
            return true
        default:
            return false
        }
    }

    // MARK: - when

    /// A `location.fix` record: an arrival is handed over, a pull is already in the timeline.
    ///
    /// Split out of `deliver` for its own sake as much as the switch's — the arrival/pull
    /// distinction is the single most misread thing in the format, and it deserves a name.
    private static func deliverFix(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        guard let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))
        else { return false }
        // A pull is state, not an event. It was loaded into the provider's timeline before the
        // run started (see `ReplayFixProvider`), so there is nothing to deliver here — and a
        // pull that found nothing carries no coordinates to deliver even in principle.
        guard source.isArrival else { return true }
        guard let latitude = record.latitude, let longitude = record.longitude else { return false }
        // Absent on `prov=bus`, and legitimately so — `LocationAcquiredEvent` carries a
        // `LocationData`, which has no accuracy field. Requiring it here rejected every
        // bus fix in the 2026-09-09 iPhone drive as an unsupported input, and with no
        // position reaching the SDK the whole drive replayed as zero registrations.
        let accuracy = record.fields["acc"].flatMap(Double.init)
        guard source == .bus || accuracy != nil else { return false }
        harness.feedFix(
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            // Absent on a fix the SDK had just taken; zero is then the truth, not a default.
            age: record.fields["age"].flatMap(Double.init) ?? 0,
            source: source
        )
        return true
    }

    /// Routes one recorded input to the seam that can replay it.
    ///
    /// Two dispatchers rather than one switch, split where the inputs themselves split: what the
    /// world told the SDK, and what the app did. `nil` from either means "not mine" and falls
    /// through; `false` means the record *was* recognised but could not be replayed, which is a
    /// finding about the capture and is counted as unsupported.
    private static func deliver(
        _ record: Scenario.Record,
        on harness: ReplayHarness,
        isFirst: Bool,
        scenarioEpoch: Date?
    ) -> Bool {
        deliverWorldInput(record, on: harness, scenarioEpoch: scenarioEpoch)
            ?? deliverAppInput(record, on: harness, isFirst: isFirst)
            ?? false
    }

    /// What reached the SDK from outside it: the OS, the location stack, the permission tier.
    private static func deliverWorldInput(
        _ record: Scenario.Record,
        on harness: ReplayHarness,
        scenarioEpoch: Date?
    ) -> Bool? {
        switch record.ev {
        case "os.callback":
            guard let id = record.fenceId, let transition = record.transition else { return false }
            // Identifier, state and how long the OS held the event. The recorded `lat`/`lon` are
            // the position the SDK *read* when the callback landed, not something CoreLocation
            // handed it — they are answered from the cache timeline, where the drive recorded them.
            harness.deliverCrossing(
                fence: id,
                transition: transition,
                // Two copies of one crossing carry the same `edate`; the runner passes it through
                // untouched so the SDK sees one event, as the phone did.
                identity: record.eventIdentity(t0: scenarioEpoch),
                evage: record.fields["evage"].flatMap(Double.init) ?? 0
            )
            return true

        case "os.monitor.stopped":
            // The OS abandoning a condition. First seen on the 2026-09-12 drive, where a relaunch
            // made CoreLocation give up all 20 at once — no earlier capture contains one, which is
            // why this seam did not exist until a drive needed it.
            guard let id = record.fenceId else { return false }
            harness.deliverMonitorStopped(fence: id)
            return true

        case "location.fix":
            return deliverFix(record, on: harness)

        case "permission.changed":
            // A real input now the authorization seam exists: `.notDetermined` reads as `.blocked`,
            // so a drive that starts before the prompt is answered registers nothing until it is.
            guard let status = record.authorizationStatus else { return false }
            harness.setAuthorization(status)
            return true

        default:
            return nil
        }
    }

    /// What the app itself did: identity, the module's own lifecycle, the process, foreground.
    private static func deliverAppInput(
        _ record: Scenario.Record,
        on harness: ReplayHarness,
        isFirst: Bool
    ) -> Bool? {
        switch record.ev {
        case "identity.changed":
            guard let ok = record.fields["ok"] else { return false }
            harness.setIdentified(ok == "true")
            return true

        case "module.init", "module.wake":
            // Drives the real launch decision, on every occurrence. After a `process.start` the
            // trigger is a fresh object, so a second module init is the relaunched process starting
            // up — exactly what the recording shows — not a duplicate to be rejected.
            harness.trigger.onModuleInit()
            // Both halves of `GeofenceModuleState.setup`, in its order: the trigger decides whether
            // to sync, then the monitor bootstrap adopts or re-registers whatever CoreLocation kept
            // while the app was dead. Launched rather than awaited because production launches it —
            // a detached `Task` off a synchronous `setup` — and the drive shows the consequence:
            // `sync.skipped` is logged before `storage.loaded`, never after. `settle` drains it.
            Task { @MainActor in await harness.wireMonitor() }
            return true

        case "device.state":
            // Battery, thermal, network and foreground state. §4 of the format decision: there is
            // no behavioural seam for these on iOS — they are recorded so a human can explain a
            // drive, and they change nothing the SDK decides. Accepted as a no-op deliberately.
            return true

        case "app.foreground":
            // The real re-arm, by the route the SDK listens on. `rearmOnForegroundIfStale` rebuilds
            // every owned condition after a long suspension, which can make the OS emit a
            // corrective crossing — so this used to be the one input the iOS composition silently
            // under-exercised while Android drove the real coordinator for it.
            harness.enterForeground()
            return true

        case "app.background":
            // Nothing in the SDK observes it. Recorded so a human can see when the drive went
            // background, which is most of why the foreground re-arm matters.
            return true

        case "process.start":
            // The harness *is* a fresh process, so the scenario's first one is already satisfied.
            // A later one is the OS relaunching a suspended app to deliver a crossing — the normal
            // background path, not a crash — so the process is re-entered rather than rejected.
            if !isFirst { harness.reenterProcess() }
            return true

        default:
            return nil
        }
    }
}

// MARK: - Record → SDK types

extension Scenario.Record {
    var latitude: Double? { fields["lat"].flatMap(Double.init) }
    var longitude: Double? { fields["lon"].flatMap(Double.init) }

    /// The OS event's own timestamp, as seconds from the scenario's `t0`.
    ///
    /// Absolute in the capture, so it needs the drive's own epoch to land on the replay's timeline.
    /// Absent from captures predating the field, and then `nil` — the runner falls back rather than
    /// inventing one.
    func eventIdentity(t0: Date?) -> TimeInterval? {
        guard let t0, let edate = fields["edate"].flatMap(Double.init) else { return nil }
        return Date(timeIntervalSince1970: edate).timeIntervalSince(t0)
    }

    /// The granted tier a `permission.changed` recorded, by the same tokens the SDK writes
    /// (`GeofenceLog.permission`). An unrecognised one fails the run rather than defaulting: every
    /// tier decides something, so guessing would replay a permission state the drive never had.
    var authorizationStatus: CLAuthorizationStatus? {
        switch fields["perm"] {
        case "not_determined": .notDetermined
        case "restricted": .restricted
        case "denied": .denied
        case "always": .authorizedAlways
        case "when_in_use": .authorizedWhenInUse
        default: nil
        }
    }
}
