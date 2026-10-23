@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

/// Inputs only: never write SDK state directly; if the inputs don't reproduce the drive, that is the
/// finding. Unsupported records fail the run, never skipped.
@available(iOS 17.0, *)
@MainActor
enum ReplayRunner {
    struct Result {
        let emitted: [[String: String]]
        let unsupported: [String]
        /// Ascending; pulls and inert records are absent.
        let stimuli: [TimeInterval]
    }

    static func run(_ scenario: Scenario, on harness: ReplayHarness) async throws -> Result {
        var unsupported: [String] = []

        let pulled = pulledReads(scenario, on: harness)
        unsupported.append(contentsOf: pulled.unsupported)
        // Ascending: `ReplayMatcher.groups` uses `lastIndex { $0 <= record.at }`.
        let stimuli = Self.stableByTime(scenario.when)
            .filter(Self.isStimulus)
            .map(\.at)
        let carried = carriedReads(scenario, on: harness)
        unsupported.append(contentsOf: carried.unsupported)
        loadRequestedFixAnswers(scenario, on: harness)
        harness.loadPulledFixes(
            stimuli: stimuli,
            samples: pulled.reads,
            carried: carried.reads
        )

        // `fixture.api.fetch` is stamped on arrival, so its `at` is the release time.
        harness.loadBoundaryAnswers(
            fetch: scenario.given.filter { $0.ev == "fixture.api.fetch" }.map(\.at).sorted()
        )

        for record in Self.stableByTime(scenario.given) where !install(record, on: harness) {
            unsupported.append("\(record.kind) \(record.ev)@\(record.at)")
        }

        try unsupported.append(contentsOf: await replayInputs(scenario, on: harness))

        try await settleFinalAnswers(on: harness)
        return Result(emitted: harness.emitted, unsupported: unsupported, stimuli: stimuli)
    }

    /// Pull records are read on demand; an incomplete sample remains unsupported.
    private static func pulledReads(
        _ scenario: Scenario,
        on harness: ReplayHarness
    ) -> (reads: [ReplayFixProvider.CachedRead], unsupported: [String]) {
        var unsupported: [String] = []
        let reads = scenario.when.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "location.fix",
                  let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:)),
                  !source.isArrival, source != .bus
            else { return nil }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else {
                // `prov=none` is the one pull with no position.
                if source == .none { return harness.emptyPull(at: record.at) }
                // Reported here: `deliverFix` accepts every pull without reading it.
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
        return (reads, unsupported)
    }

    private static func settleFinalAnswers(on harness: ReplayHarness) async throws {
        // A capture can end mid-sync; answer it so those decisions are graded.
        await harness.settleBoundaries()
        // A recorded OS reply can follow the last external stimulus. Drive only as far as that
        // input evidence, allowing the SDK's own deadlines and timeouts to run along the way.
        if let horizon = harness.fixes.requestedAnswerHorizon {
            await harness.advance(to: horizon) { await settle(harness) }
            await harness.settleBoundaries()
        }
        // A run that ends frozen keeps its replies held: name them, never wake the process to answer.
        if harness.isExecutionSuspended {
            await harness.releaseRemainingBoundaries {}
        }
        if let timeout = harness.idleTimeout { throw timeout }
    }

    /// A `note`, not a stimulus: the OS's reply to work the SDK started.
    private static func loadRequestedFixAnswers(_ scenario: Scenario, on harness: ReplayHarness) {
        let answers = scenario.note.compactMap { record -> ReplayFixProvider.CachedRead? in
            guard record.ev == "fix.received", record.fields["prov"] == "movement_resolver",
                  let latitude = record.latitude, let longitude = record.longitude,
                  let accuracy = record.fields["acc"].flatMap(Double.init)
            else { return nil }
            return harness.pulledFix(
                latitude: latitude, longitude: longitude, accuracy: accuracy,
                age: record.fields["age"].flatMap(Double.init) ?? 0, at: record.at
            )
        }
        harness.fixes.loadRequestedAnswers(
            answers,
            allowSyntheticFallback: !scenario.isRecorded,
            processStarts: scenario.when.filter { $0.ev == "process.start" }.map(\.at)
        )
    }

    /// Incomplete shapes fail closed: dropping one would hand the SDK a nil the drive never recorded.
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
                // A complete read may name any source, e.g. `os_trigger`, which isn't a `FixSource`.
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

    /// Waits for the SDK to finish what the last input started, not for a stretch of real time.
    private static func settle(_ harness: ReplayHarness) async {
        await harness.awaitIdle()
    }

    private static func replayInputs(_ scenario: Scenario, on harness: ReplayHarness) async throws -> [String] {
        var unsupported: [String] = []
        var seen: Set<String> = []
        for record in Self.stableByTime(scenario.when) {
            await harness.advance(to: record.at) { await settle(harness) }
            if let timeout = harness.idleTimeout { throw timeout }
            let isFirst = seen.insert(record.ev).inserted
            let handled: Bool
            if let execution = await deliverExecutionInput(record, on: harness) {
                handled = execution
            } else {
                handled = deliver(record, on: harness, isFirst: isFirst, scenarioEpoch: scenario.startedAt)
            }
            if let reason = await unsupportedReason(record, handled: handled, on: harness) {
                unsupported.append(reason)
            }
            await settle(harness)
            if let timeout = harness.idleTimeout { throw timeout }
        }

        return unsupported
    }

    /// A false boundary moves reads and decisions into a phase the drive never ran. `app.foreground`
    /// is not inert: it drives `rearmOnForegroundIfStale`.
    private static func isStimulus(_ record: Scenario.Record) -> Bool {
        switch record.ev {
        case "device.state", "app.background", "app.suspend":
            // A freeze starts no SDK work; what follows `app.resume` belongs to that stimulus.
            false
        case "location.fix":
            // An unreadable `prov` stays a boundary; `deliverFix` reports it as unsupported.
            record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))?.isArrival ?? true
        default:
            true
        }
    }

    /// `sorted(by:)` isn't stable and captures are full of millisecond ties; file order breaks them.
    private static func stableByTime(_ records: [Scenario.Record]) -> [Scenario.Record] {
        records.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    // MARK: - given

    private static func install(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        switch record.ev {
        case "fixture.api.fetch":
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

    private static func deliverFix(_ record: Scenario.Record, on harness: ReplayHarness) -> Bool {
        guard let source = record.fields["prov"].flatMap(GeofenceLog.FixSource.init(rawValue:))
        else { return false }
        guard source.isArrival else { return true }
        guard let latitude = record.latitude, let longitude = record.longitude else { return false }
        // Absent on `prov=bus`: `LocationAcquiredEvent` has no accuracy.
        let accuracy = record.fields["acc"].flatMap(Double.init)
        guard source == .bus || accuracy != nil else { return false }
        harness.feedFix(
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            // Absent on a fix just taken; zero is the truth, not a default.
            age: record.fields["age"].flatMap(Double.init) ?? 0,
            source: source
        )
        return true
    }

    /// A dispatcher's `nil` means "not mine" and falls through; `false` means recognised but not
    /// replayable.
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

    private static func unsupportedReason(
        _ record: Scenario.Record,
        handled: Bool,
        on harness: ReplayHarness
    ) async -> String? {
        let stamp = "\(record.kind) \(record.ev)@\(record.at)"
        guard handled else {
            return harness.isExecutionSuspended ? "\(stamp) — process suspended; no app.resume precedes it" : stamp
        }
        if record.ev == "visit.reported", await harness.hasRegisteredPolygons() {
            return "\(stamp) — polygon pass needs a fresh fix the replay cannot supply"
        }
        return nil
    }

    /// Explicit OS freeze and thaw, independent of `app.background`. While frozen only a thaw runs:
    /// replaying another stimulus would invent a callback time the drive never recorded, so it fails
    /// the run instead. A relaunch fails too: it would have to drop replies the frozen SDK still
    /// awaits, and those awaits would stay suspended for the rest of the test process. `nil` means
    /// "not mine".
    private static func deliverExecutionInput(_ record: Scenario.Record, on harness: ReplayHarness) async -> Bool? {
        switch record.ev {
        case "app.suspend":
            harness.suspendExecution()
            return true
        case "app.resume":
            guard harness.isExecutionSuspended else { return false }
            await harness.resumeExecution()
            return true
        default:
            // `process.start` too: refused while frozen; awake, `deliverAppInput` relaunches as before.
            return harness.isExecutionSuspended && isStimulus(record) ? false : nil
        }
    }

    private static func deliverWorldInput(
        _ record: Scenario.Record,
        on harness: ReplayHarness,
        scenarioEpoch: Date?
    ) -> Bool? {
        switch record.ev {
        case "os.callback":
            guard let id = record.fenceId, let transition = record.transition else { return false }
            harness.deliverCrossing(
                fence: id,
                transition: transition,
                identity: record.eventIdentity(t0: scenarioEpoch),
                evage: record.fields["evage"].flatMap(Double.init) ?? 0
            )
            return true

        case "visit.reported":
            // Older drives lack `lat`/`lon`; the SDK never reads a visit's coordinate for containment.
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
            guard let id = record.fenceId else { return false }
            harness.deliverMonitorStopped(fence: id)
            return true

        case "location.fix":
            return deliverFix(record, on: harness)

        case "permission.changed":
            guard let status = record.authorizationStatus else { return false }
            harness.setAuthorization(status)
            return true

        default:
            return nil
        }
    }

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
            // Every occurrence: after a `process.start` a second init is the relaunched process.
            harness.trigger.onModuleInit()
            // Launched, not awaited, as in production, so `sync.skipped` logs before `storage.loaded`.
            harness.taskSpawner.spawn { @MainActor in await harness.wireMonitor() }
            return true

        case "device.state":
            // No seam on iOS.
            return true

        case "app.foreground":
            harness.enterForeground()
            return true

        case "app.background":
            // Nothing in the SDK observes it.
            return true

        case "process.start":
            // A later one is the OS relaunching the app.
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

    func eventIdentity(t0: Date?) -> TimeInterval? {
        guard let t0, let edate = fields["edate"].flatMap(Double.init) else { return nil }
        return Date(timeIntervalSince1970: edate).timeIntervalSince(t0)
    }

    /// Tokens from `GeofenceLog.permission`. An unrecognised one fails the run rather than defaulting.
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
