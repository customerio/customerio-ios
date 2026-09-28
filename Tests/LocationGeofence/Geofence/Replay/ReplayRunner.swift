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
        /// When each stimulus was delivered, in virtual seconds, ascending. Pulls and inert records
        /// are absent, so the matcher groups by the boundaries the runner actually drove.
        let stimuli: [TimeInterval]
    }

    static func run(_ scenario: Scenario, on harness: ReplayHarness) async throws -> Result {
        var unsupported: [String] = []
        var seen: Set<String> = []

        // Pulled fixes go in before the first stimulus, as a timeline the provider reads from.
        // See `ReplayFixProvider`.
        let pulled = scenario.when.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "location.fix",
                  let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:)),
                  !source.isArrival, source != .bus
            else { return nil }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else {
                // `prov=none` is the one pull that legitimately carries no position.
                if source == .none { return harness.emptyPull(at: record.at) }
                // Reported here, not in `deliverFix`, which accepts every pull without reading it.
                unsupported.append("\(record.kind) \(record.ev)@\(record.at)")
                return nil
            }
            return harness.pulledFix(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                age: record.fields["age"].flatMap(Double.init) ?? 0,
                at: record.at
            )
        }
        // Ordered as delivered: `ReplayMatcher.groups` finds a decision's stimulus with
        // `lastIndex { $0 <= record.at }`, which needs an ascending list.
        let stimuli = Self.stableByTime(scenario.when)
            .filter(Self.isStimulus)
            .map(\.at)
        let carried = carriedReads(scenario, on: harness)
        unsupported.append(contentsOf: carried.unsupported)
        loadRequestedFixAnswers(scenario, on: harness)
        harness.loadPulledFixes(
            stimuli: stimuli,
            samples: pulled,
            carried: carried.reads
        )

        // `fixture.api.fetch` is stamped on arrival, so its `at` is the release time.
        harness.loadBoundaryAnswers(
            fetch: scenario.given.filter { $0.ev == "fixture.api.fetch" }.map(\.at).sorted()
        )

        // Every fixture is queued before the first stimulus, in recorded order; see `enqueueFetch`.
        for record in Self.stableByTime(scenario.given) where !install(record, on: harness) {
            unsupported.append("\(record.kind) \(record.ev)@\(record.at)")
        }

        for record in Self.stableByTime(scenario.when) {
            // Answers every boundary the drive answered before this input; see `ReplayBoundaryGate`.
            await harness.advance(to: record.at) { await settle(harness) }
            let isFirst = seen.insert(record.ev).inserted
            let handled = deliver(record, on: harness, isFirst: isFirst, scenarioEpoch: scenario.startedAt)
            if let reason = await unsupportedReason(record, handled: handled, on: harness) {
                unsupported.append(reason)
            }
            await settle(harness)
        }

        // A capture can end with a sync in flight; answer it so those decisions are graded.
        try await harness.settleBoundaries()
        return Result(emitted: harness.emitted, unsupported: unsupported, stimuli: stimuli)
    }

    /// What each fresh-fix request was answered with. A `note`, not a stimulus: it is the OS's reply
    /// to work the SDK started.
    private static func loadRequestedFixAnswers(_ scenario: Scenario, on harness: ReplayHarness) {
        harness.fixes.loadRequestedAnswers(scenario.note.compactMap { record in
            guard record.ev == "fix.received", record.fields["prov"] == "movement_resolver",
                  let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else { return nil }
            return harness.pulledFix(
                latitude: latitude, longitude: longitude, accuracy: accuracy,
                age: record.fields["age"].flatMap(Double.init) ?? 0, at: record.at
            )
        })
    }

    /// What each OS callback recorded about the fix it read to write its own line. The provider
    /// uses these only for a window the recorded reads left empty; see `ReplayFixProvider`.
    ///
    /// Incomplete shapes fail closed, as on a standalone pull: losing one would hand the SDK a nil
    /// the drive never recorded. `fixsrc=none` is the one shape that legitimately has no position.
    private static func carriedReads(
        _ scenario: Scenario,
        on harness: ReplayHarness
    ) -> (reads: [ReplayFixProvider.CachedRead], unsupported: [String]) {
        var unsupported: [String] = []
        let reads = scenario.when.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "os.callback", let raw = record.fields["fixsrc"] else { return nil }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else {
                // The source only settles whether a missing position is legitimate. A complete read
                // may name any source, e.g. the cross-platform `os_trigger` that is not a `FixSource`.
                if GeofenceLog.FixSource(rawValue: raw) == GeofenceLog.FixSource.none {
                    return harness.emptyPull(at: record.at)
                }
                unsupported.append("\(record.kind) \(record.ev)@\(record.at) fixsrc=\(raw)")
                return nil
            }
            return harness.pulledFix(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                age: record.fields["age"].flatMap(Double.init) ?? 0,
                at: record.at
            )
        }
        return (reads, unsupported)
    }

    /// Cancellation is swallowed: a cancelled run should stop pacing, not abort mid-record and
    /// report the remaining expectations as missing.
    private static func settle(_ harness: ReplayHarness) async {
        try? await ReplayHarness.letAsyncWorkRun()
    }

    /// Whether a record drove SDK work, and so bounds a window.
    ///
    /// `ReplayFixProvider` serves each read from its stimulus's window and `ReplayMatcher.groups`
    /// attributes each decision to the stimulus before it, so a boundary the SDK never had moves a
    /// read or decision into a phase the drive never ran.
    ///
    /// Not stimuli:
    ///
    /// - a **pull**, which happens inside an earlier stimulus's work and is on the provider's
    ///   timeline instead;
    /// - **`device.state` and `app.background`**, accepted as no-ops by `deliverAppInput`.
    ///   `app.foreground` is *not* inert — it drives `rearmOnForegroundIfStale`.
    private static func isStimulus(_ record: Scenario.Record) -> Bool {
        switch record.ev {
        case "device.state", "app.background":
            false
        case "location.fix":
            // An unreadable `prov` stays a boundary, and `deliverFix` reports it as unsupported.
            record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))?.isArrival ?? true
        default:
            true
        }
    }

    /// Records in time order, ties broken by the order the capture wrote them.
    ///
    /// `sorted(by:)` is not stable in Swift, and captures are full of millisecond ties (the sink
    /// stamps to the millisecond, CoreLocation delivers in bursts). The file's order is the
    /// observed order, so it is the tiebreak.
    private static func stableByTime(_ records: [Scenario.Record]) -> [Scenario.Record] {
        records.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    // MARK: - given

    private static func install(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        switch record.ev {
        case "fixture.api.fetch":
            // A failed fetch is an input too: the SDK carries on with what it had cached.
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
    private static func deliverFix(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        guard let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))
        else { return false }
        // A pull was loaded into the provider's timeline before the run (see `ReplayFixProvider`).
        guard source.isArrival else { return true }
        guard let latitude = record.latitude, let longitude = record.longitude else { return false }
        // Legitimately absent on `prov=bus`: `LocationAcquiredEvent`'s `LocationData` has no
        // accuracy field.
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
    /// `nil` from a dispatcher means "not mine" and falls through; `false` means the record was
    /// recognised but could not be replayed, and is counted as unsupported.
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

    /// Why an input the harness dispatched still cannot be graded, or `nil` when it can.
    ///
    /// A `visit.reported` wakes `evaluateAllPolygons(requiresFreshFix: true)`. With a polygon
    /// registered its verdict is refused rather than graded; a circle-only drive's visits are
    /// graded. See `ReplayHarness.hasRegisteredPolygons`.
    private static func unsupportedReason(
        _ record: Scenario.Record,
        handled: Bool,
        on harness: ReplayHarness
    ) async -> String? {
        let stamp = "\(record.kind) \(record.ev)@\(record.at)"
        guard handled else { return stamp }
        if record.ev == "visit.reported", await harness.hasRegisteredPolygons() {
            return "\(stamp) — polygon pass needs a fresh fix the replay cannot supply"
        }
        return nil
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
            // The recorded `lat`/`lon` are the SDK's own read, answered from the cache timeline.
            harness.deliverCrossing(
                fence: id,
                transition: transition,
                // Two copies of one crossing carry the same `edate`, so the SDK sees one event.
                identity: record.eventIdentity(t0: scenarioEpoch),
                evage: record.fields["evage"].flatMap(Double.init) ?? 0
            )
            return true

        case "visit.reported":
            // `lat`/`lon` are what CoreLocation handed over; older drives lack them. The SDK treats
            // a visit as a wake signal and never reads its coordinate for containment.
            let edge = record.fields["edge"]
            let delay = record.fields["delay"].flatMap(Double.init) ?? 0
            let reportedAt = harness.now.addingTimeInterval(-delay)
            let isArrival = edge == "arrival"
            harness.visitMonitor.deliver(
                GeofenceVisit(
                    coordinate: LocationData(
                        latitude: record.fields["lat"].flatMap(Double.init) ?? 0,
                        longitude: record.fields["lon"].flatMap(Double.init) ?? 0
                    ),
                    horizontalAccuracy: record.fields["acc"].flatMap(Double.init) ?? -1,
                    arrivalDate: isArrival ? reportedAt : .distantPast,
                    departureDate: isArrival ? .distantFuture : reportedAt
                )
            )
            return true

        case "os.monitor.stopped":
            // The OS abandoning a condition (`.unmonitored`).
            guard let id = record.fenceId else { return false }
            harness.deliverMonitorStopped(fence: id)
            return true

        case "location.fix":
            return deliverFix(record, on: harness)

        case "permission.changed":
            // `.notDetermined` reads as blocked, so a drive registers nothing until the prompt is
            // answered.
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
            // On every occurrence: after a `process.start` a second module init is the relaunched
            // process starting up, not a duplicate.
            harness.trigger.onModuleInit()
            // Both halves of `GeofenceModuleState.setup`, in its order. Launched, not awaited, as
            // production does, so `sync.skipped` logs before `storage.loaded`. `settle` drains it.
            Task { @MainActor in await harness.wireMonitor() }
            return true

        case "device.state":
            // Battery, thermal, network and foreground state: context for a human, no seam on iOS.
            return true

        case "app.foreground":
            // `rearmOnForegroundIfStale` rebuilds every owned condition after a long suspension,
            // which can make the OS emit a corrective crossing.
            harness.enterForeground()
            return true

        case "app.background":
            // Nothing in the SDK observes it; recorded for a human reading the drive.
            return true

        case "process.start":
            // The harness is already a fresh process. A later one is the OS relaunching the app to
            // deliver a crossing, so the process is re-entered.
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
    /// Absolute in the capture, so it needs the drive's epoch. `nil` for captures predating the
    /// field; the caller then falls back to `evage`.
    func eventIdentity(t0: Date?) -> TimeInterval? {
        guard let t0, let edate = fields["edate"].flatMap(Double.init) else { return nil }
        return Date(timeIntervalSince1970: edate).timeIntervalSince(t0)
    }

    /// The authorization a `permission.changed` recorded, by the tokens `GeofenceLog.permission`
    /// writes. An unrecognised one fails the run rather than defaulting to a state the drive never had.
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
