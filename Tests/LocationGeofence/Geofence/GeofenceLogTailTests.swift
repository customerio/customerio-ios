@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// Producer-side contract for the geofence diagnostics tail.
///
/// The tail is an untyped string contract consumed by a parser that lives off-device and in
/// another language, so there is no round trip to assert. What can be asserted here is the half we
/// own: that every geofence logger method emits a machine key and a replay classification, that no
/// value can break the parser's whitespace split, and that precise coordinates stay behind their
/// flag.
///
/// Without this, renaming `lat=` to `latitude=` costs a whole field campaign's coordinates and
/// nobody finds out until someone tries to analyse the drive.
@Suite("Geofence log tail", .serialized)
struct GeofenceLogTailTests {
    // MARK: - Test double

    /// Captures formatted messages. Deliberately not `LoggerMock`: the generated mock records
    /// invocation counts, and what these tests need is the exact string.
    private final class CapturingLogger: Logger, @unchecked Sendable {
        private let lock = NSLock()
        private var captured: [String] = []

        var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return captured
        }

        var logLevel: CioLogLevel = .debug
        func setLogDispatcher(_: ((CioLogLevel, String) -> Void)?) {}
        func setLogLevel(_ level: CioLogLevel) {
            logLevel = level
        }

        func debug(_ message: String, _ tag: String?) {
            record(message, tag)
        }

        func info(_ message: String, _ tag: String?) {
            record(message, tag)
        }

        /// Mirrors `LoggerImpl.formatMessage`, which appends the description to the **whole**
        /// message. A double that quietly dropped the error let a record ship whose tail was no
        /// longer last, and every assertion here passed anyway.
        func error(_ message: String, _ tag: String?, _ error: Error?) {
            record(error.map { "\(message) Error: \($0.localizedDescription)" } ?? message, tag)
        }

        private func record(_ message: String, _ tag: String?) {
            lock.lock()
            defer { lock.unlock() }
            captured.append(tag.map { "[\($0)] \(message)" } ?? message)
        }
    }

    /// Mirrors what the off-device parser does: split on the **last** delimiter, then accept the
    /// remainder only if every token is a `key=value` pair.
    private func parseTail(_ message: String) -> [String: String]? {
        guard let range = message.range(of: GeofenceLog.delimiter, options: .backwards) else { return nil }
        let tail = String(message[range.upperBound...])
        var fields: [String: String] = [:]
        for token in tail.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            fields[String(parts[0])] = String(parts[1])
        }
        return fields.isEmpty ? nil : fields
    }

    /// One entry per geofence logger method, paired with the keys its record must carry.
    ///
    /// Enumerated by hand because Swift cannot reflect over an
    /// extension's methods: a new method added without a line here is simply uncovered, while a
    /// *renamed key* on anything listed here fails loudly, which is the failure this exists to catch.
    private struct Invocation {
        let name: String
        /// The `ev=` this record must emit. Pinned per row, not just collected into a set: a set
        /// is identical whether two records keep their keys or swap them, and a swap silently
        /// inverts what every capture says the SDK decided.
        let ev: String
        let requiredKeys: [String]
        let run: (Logger) -> Void
    }

    private var sampleLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.2557, longitude: -79.0713),
            altitude: 0,
            horizontalAccuracy: 48,
            verticalAccuracy: 10,
            course: 91,
            speed: 18.3,
            timestamp: Date()
        )
    }

    private var invocations: [Invocation] {
        let location = sampleLocation
        return [
            Invocation(name: "invalidRegionDropped", ev: "registration.rejected", requiredKeys: ["id", "why"]) { $0.geofenceInvalidRegionDropped("notl core", reason: .unusableCircle) },
            Invocation(name: "invalidCoordinates", ev: "registration.rejected", requiredKeys: ["id", "why"]) { $0.geofenceInvalidCoordinatesForRegion("notl_core") },
            Invocation(name: "monitoringFailed", ev: "os.monitor.failed", requiredKeys: ["id", "ok"]) { $0.geofenceMonitoringFailed(region: "notl_core", error: GeofenceApiError.transport) },
            Invocation(name: "streamFailed", ev: "os.stream.failed", requiredKeys: ["ok"]) { $0.geofenceMonitorEventStreamFailed(error: GeofenceApiError.transport) },
            Invocation(name: "stoppedMonitoring", ev: "os.monitor.stopped", requiredKeys: ["id"]) { $0.geofenceMonitorStoppedMonitoringRegion("notl_core") },
            Invocation(name: "regionsRegistered", ev: "registration.applied", requiredKeys: ["n", "ids", "mvmt"]) { $0.geofenceRegionsRegistered(identifiers: ["a", "b"], movementTrigger: "cio_movement_trigger") },
            Invocation(name: "permissionUnavailable", ev: "permission.changed", requiredKeys: ["perm", "why"]) { $0.geofencePermissionUnavailable(currentStatus: .denied) },
            Invocation(name: "backgroundUnavailable", ev: "permission.changed", requiredKeys: ["perm", "why"]) { $0.geofenceBackgroundDeliveryUnavailable(currentStatus: .authorizedWhenInUse) },
            Invocation(name: "backgroundAvailable", ev: "permission.changed", requiredKeys: ["perm", "ok"]) { $0.geofenceBackgroundDeliveryAvailable(currentStatus: .authorizedAlways) },
            Invocation(name: "moduleInitialized", ev: "module.init", requiredKeys: ["launch"]) { $0.geofenceModuleInitialized(launchReason: .appStart) },
            Invocation(name: "moduleWoke", ev: "module.wake", requiredKeys: ["launch"]) { $0.geofenceModuleWoke(launchReason: .locationEvent) },
            Invocation(name: "callbackReceived", ev: "os.callback.received", requiredKeys: ["id", "t", "buf", "fixsrc", "acc", "age", "sim", "evage"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .enter, fix: location, source: .managerCache, eventDate: Date(timeIntervalSinceNow: -3), buffered: false) },
            Invocation(name: "callbackReceivedNoFix", ev: "os.callback.received", requiredKeys: ["id", "t", "fixsrc"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .exit, fix: nil, source: .none) },
            Invocation(name: "info", ev: "info", requiredKeys: ["why"]) { $0.geofenceInfo("os_state_unusable", fields: [("id", "notl_core"), ("state", "unknown")]) },
            Invocation(name: "callbackDropped", ev: "os.callback.dropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceCallbackDropped(identifier: "notl_core", transition: .enter, reason: "movement_trigger_not_exit") },
            Invocation(name: "fixReceived", ev: "fix.received", requiredKeys: ["prov"]) { $0.geofenceFixReceived(location, source: "movement_pass") },
            Invocation(name: "fixQuality", ev: "os.callback.received", requiredKeys: ["fixsrc", "acc", "age"]) { $0.geofenceCallbackReceived(identifier: "q", transition: .enter, fix: location, source: .freshRequest) },
            Invocation(name: "deliverySent", ev: "delivery.sent", requiredKeys: ["id", "t", "via"]) { $0.geofenceDeliverySent(geofenceId: "notl_core", transition: .enter, via: "http") },
            Invocation(name: "deliveryQueued", ev: "delivery.queued", requiredKeys: ["id", "t", "via"]) { $0.geofenceDeliveryQueued(geofenceId: "notl_core", transition: .enter, via: "event_bus") },
            Invocation(name: "deliveryFailed", ev: "delivery.failed", requiredKeys: ["id", "t", "ok", "why"]) { $0.geofenceDeliveryFailed(geofenceId: "notl_core", transition: .exit, error: .transport) },
            Invocation(name: "transitionAccepted", ev: "transition.accepted", requiredKeys: ["id", "t", "n"]) { $0.geofenceTransitionAccepted(geofenceId: "notl_core", transition: .enter, rows: 2) },
            Invocation(name: "transitionSynthesized", ev: "transition.synthesized", requiredKeys: ["id", "t", "why"]) { $0.geofenceTransitionSynthesized(geofenceId: "notl_core", transition: .enter) },
            Invocation(name: "baselineRefused", ev: "baseline.refused", requiredKeys: ["id", "t", "why"]) { $0.geofenceBaselineRefused(identifier: "notl_core", transition: .enter, reason: "newer_baseline") },
            Invocation(name: "eventSuppressed", ev: "transition.suppressed", requiredKeys: ["id", "t", "why", "cd"]) { $0.geofenceEventSuppressed(geofenceId: "notl_core", transition: .enter, cooldownRemaining: 42) },
            Invocation(name: "droppedAnonymous", ev: "transition.dropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceTransitionDroppedAnonymous(geofenceId: "notl_core", transition: .exit) },
            Invocation(name: "pendingPersistFailed", ev: "storage.write.failed", requiredKeys: ["id", "t", "ok"]) { $0.geofencePendingPersistFailed(geofenceId: "notl_core", transition: .exit) },
            Invocation(name: "syncSkipped", ev: "sync.skipped", requiredKeys: ["why"]) { $0.geofenceSyncSkipped(reason: .noIdentifiedUser) },
            Invocation(name: "syncSkippedFresh", ev: "sync.skipped", requiredKeys: ["why"]) { $0.geofenceSyncSkippedFresh() },
            Invocation(name: "syncFetchFailed", ev: "api.fetch.result", requiredKeys: ["ok", "why"]) { $0.geofenceSyncFetchFailed(error: .http(statusCode: 503)) },
            Invocation(name: "apiFetchResult", ev: "api.fetch.result", requiredKeys: ["ok", "n", "ms"]) { $0.geofenceApiFetchResult(returnedCount: 30, elapsed: 0.42) },
            Invocation(name: "syncCompleted", ev: "sync.completed", requiredKeys: ["n", "mvmt", "ms"]) { $0.geofenceSyncCompleted(requestedCount: 19, movementTriggerRequested: true, acceptedCount: 19, movementTriggerAccepted: true, elapsed: 1.5) },
            Invocation(name: "registrationDiff", ev: "registration.diff", requiredKeys: ["nadd", "nrem", "nkeep"]) { $0.geofenceRegistrationDiff(added: 3, removed: 2, unchanged: 17) },
            Invocation(name: "rankEvaluated", ev: "rank.evaluated", requiredKeys: ["ncand", "n", "ranked", "evicted"]) { $0.geofenceRankEvaluated(candidates: 30, selectedCount: 2, selected: ["a", "b"], evicted: ["c"], edgeDistances: ["a": 120, "b": 340]) },
            Invocation(name: "movementTrigger", ev: "movement.exit", requiredKeys: ["tier"]) { $0.geofenceMovementTrigger(tier: .localRerank) },
            Invocation(name: "movementTriggerRegistered", ev: "movement.registered", requiredKeys: ["rad"]) { $0.geofenceMovementTriggerRegistered(latitude: 43.2, longitude: -79.0, radius: 500) },
            Invocation(name: "movementRearmed", ev: "movement.rearmed", requiredKeys: ["why"]) { $0.geofenceMovementRearmedAfterFailedRefresh() },
            Invocation(name: "allRegionsDropped", ev: "api.fetch.unreadable", requiredKeys: ["ok", "n", "why"]) { $0.geofenceAllRegionsDropped(count: 4) },
            Invocation(name: "callbackDispatched", ev: "os.callback.dispatched", requiredKeys: ["id", "t"]) { $0.geofenceCallbackDispatched(identifier: "notl_core", transition: .enter) },
            Invocation(name: "polygonTransition", ev: "polygon.transition", requiredKeys: ["id", "t", "by"]) { $0.geofencePolygonTransition(identifier: "notl_core", transition: .enter, confirmedByFix: true) },
            Invocation(name: "polygonPassSkipped", ev: "polygon.pass.skipped", requiredKeys: ["why"]) { $0.geofencePolygonPassSkipped(reason: .passInFlight) },
            Invocation(name: "polygonEvaluationRequested", ev: "polygon.evaluation.requested", requiredKeys: ["id", "why"]) { $0.geofencePolygonEvaluationRequested(identifier: "notl_core", reason: .newPolygon) },
            Invocation(name: "polygonDropped", ev: "registration.rejected", requiredKeys: ["id", "why", "rad", "lim"]) { $0.geofencePolygonExceedsMonitoringLimit(identifier: "notl_core", radius: 12000, limit: 10000) },
            Invocation(name: "polygonWakePass", ev: "polygon.wake.pass", requiredKeys: ["rad", "n"]) { $0.geofencePolygonWakePass(radius: 420, polygonCount: 3) },
            Invocation(name: "polygonVerdict", ev: "polygon.verdict", requiredKeys: ["id", "m", "edge", "acc", "age"]) { $0.geofencePolygonVerdict(identifier: "notl_core", membership: .inside, signedEdgeDistance: -80, horizontalAccuracy: 12, fixAge: 3.5) },
            Invocation(name: "polygonUndelivered", ev: "polygon.undelivered", requiredKeys: ["id", "why"]) { $0.geofencePolygonNotDelivered(identifier: "notl_core", outcome: .suppressedInitialOutside) },
            Invocation(name: "polygonUndecided", ev: "polygon.undecided", requiredKeys: ["id", "why", "edge", "acc"]) { $0.geofencePolygonUndecided(identifier: "notl_core", reason: .withinAccuracy, signedEdgeDistance: -4, horizontalAccuracy: 12) },
            Invocation(name: "wakeRadiusChosen", ev: "movement.radius.chosen", requiredKeys: ["rad", "from"]) { $0.geofenceWakeRadiusChosen(radius: 640, anchorIsLiveFix: true) },
            Invocation(name: "movementFixResolved", ev: "movement.fix.resolved", requiredKeys: ["age", "prov", "spd", "for"]) { $0.geofenceMovementFixResolved(ageSeconds: 12.5, requested: true, speed: 13.4, purpose: .movement) },
            Invocation(name: "movementFixStale", ev: "movement.fix.requested", requiredKeys: ["age", "why"]) { $0.geofenceMovementFixStale(ageSeconds: 900) },
            Invocation(name: "movementFixRequestFailed", ev: "movement.fix.failed", requiredKeys: ["ok", "why", "ms"]) { $0.geofenceMovementFixRequestFailed(fallingBackToCached: true, elapsed: 5) },
            Invocation(name: "baselineHealed", ev: "baseline.healed", requiredKeys: ["id", "t"]) { $0.geofenceBaselineHealed(identifier: "notl_core", transition: .enter) },
            Invocation(name: "contradictionEvaluated", ev: "contradiction.evaluated", requiredKeys: ["id", "t", "dly", "win"]) { $0.geofenceContradictionEvaluated(identifier: "notl_core", transition: .enter, delaySinceAdd: 1.25, insideWindow: true) },
            Invocation(name: "contradictionRefused", ev: "contradiction.refused", requiredKeys: ["id", "t", "dist", "rad", "edge", "acc"]) { $0.geofenceEventRefusedByContradiction(identifier: "notl_core", transition: .enter, distanceFromCenter: 1400, radius: 1000, accuracy: 48) },
            Invocation(name: "syncSuperseded", ev: "sync.superseded", requiredKeys: ["why"]) { $0.geofenceSyncSupersededByUserChange() },
            Invocation(name: "resetCompleted", ev: "module.reset", requiredKeys: ["ok"]) { $0.geofenceResetCompleted() },
            Invocation(name: "resetSuperseded", ev: "module.reset", requiredKeys: ["ok", "why"]) { $0.geofenceResetSuperseded() },
            Invocation(name: "firstRunRearm", ev: "movement.rearmed", requiredKeys: ["why"]) { $0.geofenceFirstRunRearm() },
            Invocation(name: "regionsAdopted", ev: "registration.adopted", requiredKeys: ["n"]) { $0.geofenceRegionsAdopted(count: 4) },
            Invocation(name: "foregroundRearm", ev: "registration.rearmed", requiredKeys: ["n", "why"]) { $0.geofenceForegroundRearm(count: 4) },
            Invocation(name: "storageLoaded", ev: "storage.loaded", requiredKeys: ["n", "anchor"]) { $0.geofenceStorageLoaded(regionCount: 30, hasAnchor: true) },
            Invocation(name: "queueRowsDropped", ev: "queue.rows_dropped", requiredKeys: ["why", "n", "total"]) { $0.geofenceQueueRowsDropped(count: 1, of: 3) },
            Invocation(name: "queueUnreadable", ev: "queue.unreadable", requiredKeys: ["why"]) { $0.geofenceQueueUnreadable(reason: .readFailed) },
            Invocation(name: "droppedQueueUnreadable", ev: "transition.dropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceTransitionDroppedQueueUnreadable(geofenceId: "notl_core", transition: .enter) }
        ]
    }

    /// Runs every invocation against one logger, for the tests that care about the whole set.
    private func runAll(_ logger: Logger) {
        for invocation in invocations {
            invocation.run(logger)
        }
    }

    // MARK: - Contract

    /// Runs `body` with diagnostics forced on or off, restoring the previous value after.
    private func withDiagnostics<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        try DiagnosticsGateTesting.withDiagnostics(enabled, body)
    }

    @Test
    func everyRecord_expectMachineKeyAndReplayClassification() {
        withDiagnostics(true) {

            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)

                guard let message = logger.messages.last, let fields = parseTail(message) else {
                    Issue.record("\(invocation.name): no parseable tail in '\(logger.messages.last ?? "<nothing logged>")'")
                    continue
                }
                #expect(
                    fields["ev"] == invocation.ev,
                    "\(invocation.name): expected ev=\(invocation.ev), got '\(fields["ev"] ?? "<absent>")'"
                )
                #expect(
                    ["in", "out", "obs"].contains(fields["io"] ?? ""),
                    "\(invocation.name): io= must be in/out/obs, got '\(fields["io"] ?? "<absent>")'"
                )
                for key in invocation.requiredKeys {
                    #expect(fields[key] != nil, "\(invocation.name): missing \(key)= in '\(message)'")
                }
            }
        }
    }

    /// One resolver serves five decisions, so a speed sample is only usable once you can tell
    /// which asked for it — the wake margin is calibrated from the movement caller alone.
    @Test
    func movementFixResolved_expectTheAskingDecisionNamed() {
        withDiagnostics(true) {
            for purpose in [GeofenceFixPurpose.movement, .contradictionGate, .baselineHeal, .pendingEvents, .polygon] {
                let logger = CapturingLogger()
                logger.geofenceMovementFixResolved(ageSeconds: 1, requested: false, speed: 5, purpose: purpose)
                #expect(parseTail(logger.messages.last ?? "")?["for"] == purpose.rawValue)
            }
            // Distinct tokens, or the split says nothing.
            #expect(Set([GeofenceFixPurpose.movement, .contradictionGate, .baselineHeal, .pendingEvents, .polygon].map(\.rawValue)).count == 5)
        }
    }

    /// CoreLocation reports -1 for "no speed", which is not the same as stationary. Carrying it
    /// through would put a fabricated -1.0 into a calibration sample that averages speeds.
    @Test
    func movementFixResolved_givenNoSpeedOnTheFix_expectTheKeyOmitted() {
        withDiagnostics(true) {
            let stationary = CapturingLogger()
            stationary.geofenceMovementFixResolved(ageSeconds: 1, requested: false, speed: 0)
            #expect(parseTail(stationary.messages.last ?? "")?["spd"] == "0.0")

            let unknown = CapturingLogger()
            unknown.geofenceMovementFixResolved(ageSeconds: 1, requested: false, speed: -1)
            #expect(parseTail(unknown.messages.last ?? "")?["spd"] == nil)

            let absent = CapturingLogger()
            absent.geofenceMovementFixResolved(ageSeconds: 1, requested: false)
            #expect(parseTail(absent.messages.last ?? "")?["spd"] == nil)
        }
    }

    @Test
    func deliveryFailure_expectDistinctReasonTokenPerCause() {
        // The token is the whole value of this record now that it carries no verdict: it is what
        // separates an offline device from a misconfigured one when someone reads a drive.
        let errors: [BackgroundDeliveryHttpError] = [
            .missingApiHost, .missingCdpApiKey, .invalidRequest, .transport,
            .http(statusCode: 401), .http(statusCode: 503)
        ]
        let tokens = errors.map(\.diagnosticReason)
        #expect(Set(tokens).count == tokens.count, "two causes share a token: \(tokens)")
        // Tokens ride a whitespace-split tail.
        #expect(tokens.allSatisfy { !$0.contains(" ") }, "a reason token contains whitespace")
        // 0 is synthesized when there was no response at all; reporting it as a status invites
        // the reader to believe the backend answered.
        #expect(BackgroundDeliveryHttpError.http(statusCode: 0).diagnosticReason == "no_response")
        #expect(BackgroundDeliveryHttpError.http(statusCode: 503).diagnosticReason == "http_503")
    }

    /// The module's whole diagnostic vocabulary, hoisted out of the test so the assertion stays
    /// readable as rows are added.
    private static let declaredVocabulary: Set<String> = [
        "api.fetch.result",
        "api.fetch.unreadable",
        "baseline.healed",
        "baseline.refused",
        "contradiction.evaluated",
        "contradiction.refused",
        "delivery.failed",
        "delivery.queued",
        "delivery.sent",
        "fix.received",
        "info",
        "module.init",
        "module.reset",
        "module.wake",
        "movement.exit",
        "movement.fix.failed",
        "movement.fix.requested",
        "movement.fix.resolved",
        "movement.radius.chosen",
        "movement.rearmed",
        "movement.registered",
        "os.callback.dispatched",
        "os.callback.dropped",
        "os.callback.received",
        "os.monitor.failed",
        "os.monitor.stopped",
        "os.stream.failed",
        "permission.changed",
        "polygon.evaluation.requested",
        "polygon.pass.skipped",
        "polygon.transition",
        "polygon.undecided",
        "polygon.undelivered",
        "polygon.verdict",
        "polygon.wake.pass",
        "queue.rows_dropped",
        "queue.unreadable",
        "rank.evaluated",
        "registration.adopted",
        "registration.applied",
        "registration.diff",
        "registration.rearmed",
        "registration.rejected",
        "storage.loaded",
        "storage.write.failed",
        "sync.completed",
        "sync.skipped",
        "sync.superseded",
        "transition.accepted",
        "transition.dropped",
        "transition.suppressed",
        "transition.synthesized"
    ]

    @Test
    func everyRecord_expectTheDeclaredVocabulary() {
        // Companion to the per-row `ev` pin above, catching what a per-row check cannot: a key
        // removed from the module entirely, or a row added to the table without being declared
        // here. It does NOT see a record that exists in the module but was never added to the
        // table — `seen` is built from the table, not from the source. `fence.cataloged` is the
        // standing proof of that limit.
        //
        // `fence.cataloged` is absent on purpose: it is emitted by a private helper driven through
        // `api.fetch.result`, so it cannot be a row here. It carries its own `ev` assertion in
        // `fenceCatalog_...` below. Every other key the module emits is listed.
        let expected = Self.declaredVocabulary
        var seen: Set<String> = []
        withDiagnostics(true) {
            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)
                if let ev = parseTail(logger.messages.last ?? "")?["ev"] { seen.insert(ev) }
            }
        }
        #expect(seen == expected, "vocabulary drift.\n  added:   \(seen.subtracting(expected).sorted())\n  missing: \(expected.subtracting(seen).sorted())")
    }

    @Test
    func everyRecord_expectProseAndTailSeparated() {
        withDiagnostics(true) {

            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)
                guard let message = logger.messages.last else { continue }

                // Prose in front, machine-readable behind. A record that is all tail has lost the
                // human-readable half the console still depends on.
                let head = message.components(separatedBy: GeofenceLog.delimiter)[0]
                #expect(head.hasPrefix("[Geofence] "), "\(invocation.name): lost its tag — '\(message)'")
                #expect(head.count > "[Geofence] ".count, "\(invocation.name): has no prose — '\(message)'")
                #expect(!head.contains("ev="), "\(invocation.name): machine fields leaked into the prose — '\(message)'")
            }
        }
    }

    @Test
    func everyValue_expectNoWhitespace() {
        withDiagnostics(true) {

            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)
                guard let message = logger.messages.last,
                      let range = message.range(of: GeofenceLog.delimiter, options: .backwards)
                else { continue }

                for token in message[range.upperBound...].split(separator: " ") {
                    #expect(
                        token.split(separator: "=", maxSplits: 1).count == 2,
                        "\(invocation.name): token '\(token)' is not key=value — a value contained a space"
                    )
                }
            }
        }
    }

    // MARK: - The gate

    @Test
    func everyRecord_givenDiagnosticsOff_expectOutputUnchangedFromBeforeInstrumentation() {
        withDiagnostics(false) {

            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)
                guard let message = logger.messages.last else { continue }

                // The whole guarantee in one assertion: a customer build that ships with debug logging
                // left on sees exactly the prose it saw before this instrumentation existed. Not "sees
                // only the safe fields" — sees nothing new at all, so no field added to the tail later
                // needs a privacy review of its own.
                #expect(
                    !message.contains(GeofenceLog.delimiter),
                    "\(invocation.name): emitted a tail with diagnostics off — '\(message)'"
                )
                #expect(!message.contains("ev="), "\(invocation.name): leaked a machine key — '\(message)'")
            }
        }
    }

    @Test
    func everyRecord_givenDiagnosticsOff_expectNoDiagnosticKeyAnywhere() {
        withDiagnostics(false) {

            let logger = CapturingLogger()
            runAll(logger)

            // Spot-checks the classes of value the harness cares about, including the ones that are
            // harmless in isolation. The point is that "harmless in isolation" stopped being the test.
            for message in logger.messages {
                for key in ["lat=", "lon=", "alt=", "spd=", "brg=", "rlat=", "rlon=", "acc=", "age=", "fixsrc=", "io=", "why="] {
                    #expect(!message.contains(key), "\(key) leaked with diagnostics off: '\(message)'")
                }
            }
        }
    }

    @Test
    func everyRecord_givenDiagnosticsOn_expectFullDetail() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            runAll(logger)
            let joined = logger.messages.joined(separator: "\n")

            #expect(joined.contains("lat="))
            #expect(joined.contains("lon="))
            #expect(joined.contains("acc="))
            #expect(joined.contains("fixsrc="))
        }
    }

    @Test
    func listValues_expectSeparatorsSurviveTheTailBuilder() {
        // Regression: `sanitize` folds the format's separators so an untrusted id cannot split a
        // field, but it must not be applied to a value that composed those separators on purpose.
        // Folding them turned `ids=a,b` into `ids=a_b` and `ranked=x:120` into `ranked=x_120`,
        // which no unit test noticed and a device capture did.
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceRankEvaluated(
                candidates: 3,
                selectedCount: 2,
                selected: ["alpha", "beta"],
                evicted: ["gamma"],
                edgeDistances: ["alpha": 120, "beta": 340]
            )
            let message = logger.messages.last ?? ""
            #expect(message.contains("ranked=alpha:120,beta:340"), "ranked lost its separators: \(message)")
            #expect(message.contains("evicted=gamma"), "evicted malformed: \(message)")
        }
    }

    @Test
    func proseHalf_expectIdenticalWhicheverWayTheGateIsSet() {
        // The prose is what a customer reads and what existing tests assert on. Enabling
        // diagnostics must append to it and never rewrite it.
        for invocation in invocations {
            let off = CapturingLogger()
            withDiagnostics(false) { invocation.run(off) }

            let on = CapturingLogger()
            withDiagnostics(true) { invocation.run(on) }

            guard let offMessage = off.messages.last, let onMessage = on.messages.last else { continue }
            let onProse = onMessage.components(separatedBy: GeofenceLog.delimiter)[0]
            #expect(
                onProse == offMessage,
                "\(invocation.name): prose differs between gate states\n  off: \(offMessage)\n  on:  \(onProse)"
            )
        }
    }

    // MARK: - Value formatting

    @Test
    func sanitize_givenWhitespaceInIdentifier_expectFolded() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceTransitionAccepted(geofenceId: "niagara on the lake", transition: .enter, rows: 1)

            // Workspace-authored identifiers can contain anything; the parser splits on whitespace.
            #expect(parseTail(logger.messages.last ?? "")?["id"] == "niagara_on_the_lake")
        }
    }

    @Test
    func token_givenProse_expectSnakeCase() {
        #expect(GeofenceLog.token("No identified user") == "no_identified_user")
        #expect(GeofenceLog.token("http(statusCode: 503)") == "http_statuscode_503")
        #expect(GeofenceLog.token("") == "unknown")
    }

    @Test
    func skipReason_expectProseAndTokenBothPresent() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceSyncSkipped(reason: .noLastSyncAnchor)

            let message = logger.messages.last ?? ""
            // The prose half must be identical between the two gate states, because it is
            // what a human reads and what an existing test may assert on.
            #expect(message.hasPrefix("[Geofence] Sync skipped: no last-sync anchor to restore from"))
            #expect(parseTail(message)?["why"] == "no_last_sync_anchor")
        }
    }

    @Test
    func list_givenMoreThanLimit_expectTruncationMarker() {
        let values = (1 ... 30).map { "id\($0)" }
        let rendered = GeofenceLog.list(values, limit: 25)
        #expect(rendered?.hasSuffix(",+5") == true)
        #expect(GeofenceLog.list([]) == nil)
    }

    @Test
    func tokenValues_givenSeparatorsInIdentifier_expectFolded() {
        // The whitespace test elsewhere passes whether or not token fields are sanitized, because
        // `tail` folds whitespace for every value. It never covered the characters the format
        // itself uses, and every `id` call site went unprotected behind it.
        withDiagnostics(true) {
            for raw in ["store,north", "a=b", "aisle:3", "wing|west"] {
                let logger = CapturingLogger()
                logger.geofenceTransitionAccepted(geofenceId: raw, transition: .enter, rows: 1)
                let tail = parseTail(logger.messages.last ?? "")
                #expect(tail?["id"] != nil, "no id for \(raw)")
                let id = tail?["id"] ?? ""
                #expect(!id.contains(where: { "=,:|".contains($0) }), "id kept a separator: \(id)")
            }
        }
    }

    @Test
    func fieldBuilders_givenDiagnosticsOff_expectNeverEvaluated() {
        // The gate's worth is that a coordinate is never *computed*, not merely never printed.
        // Nothing else here pins that: every other test asserts on output, so a shim rewritten to
        // `let built = fields(); return GeofenceLog.tail(ev, io, built)` would leave them all
        // green while running a distance map over every candidate on every background wake.
        var builds = 0
        let fields: () -> [(String, String?)] = {
            builds += 1
            return [("lat", "37.45000"), ("lon", "-122.08400")]
        }

        withDiagnostics(false) {
            #expect(GeofenceLog.tail("probe", .output, fields()).isEmpty)
            #expect(builds == 0, "GeofenceLog.tail evaluated its fields with the gate off")

            // Through the call-site shim as well: it takes an autoclosure and hands it to another
            // one, and that re-wrapping is the part easy to lose in a refactor.
            let logger = CapturingLogger()
            #expect(logger.geofenceTail("probe", .output, fields()).isEmpty)
            #expect(builds == 0, "Logger.geofenceTail evaluated its fields with the gate off")
        }

        // Proves the assertions above are not passing because the closure is simply unreachable.
        withDiagnostics(true) {
            #expect(GeofenceLog.tail("probe", .output, fields()).contains("lat=37.45000"))
            #expect(builds == 1)
        }
    }

    // MARK: - Fence catalog

    /// A ring in GeoJSON order (longitude first) and CLOSED, as the wire sends it — the closing
    /// position repeats the first, which the catalog must drop.
    private func catalogPolygonRegion(id: String = "22250", vertices: Int = 4) -> GeofenceApiRegion {
        // A regular ring, NOT a diagonal. Collinear points enclose no area, so the kernel rejects
        // them and every catalog assertion silently exercises the fallback instead of the branch
        // that reads the kernel's own list.
        var ring = (0 ..< vertices).map { i -> [Double] in
            let angle = 2 * Double.pi * Double(i) / Double(vertices)
            return [55.184004 + 0.0015 * cos(angle), 25.109908 + 0.0015 * sin(angle)]
        }
        if let first = ring.first { ring.append(first) }
        return GeofenceApiRegion(
            id: id,
            name: "Polygon Test",
            shape: "polygon",
            latitude: nil,
            longitude: nil,
            radius: nil,
            geometry: GeofenceApiGeometry(type: "Polygon", coordinates: [ring]),
            enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.109908, longitude: 55.184004, baseRadiusM: 625),
            carriesPolygonFields: true,
            externalId: nil,
            transitionTypes: ["enter", "exit"],
            lastUpdated: 0,
            geosetIds: ["4471"],
            metadata: nil
        )
    }

    private func catalogRegion(id: String = "11125", name: String? = "Momo Dubai Test") -> GeofenceApiRegion {
        GeofenceApiRegion(
            id: id,
            name: name,
            shape: "circle",
            latitude: 25.109908,
            longitude: 55.184004,
            radius: 150,
            geometry: nil,
            enclosingCircle: nil,
            carriesPolygonFields: false,
            externalId: nil,
            transitionTypes: ["enter", "exit"],
            lastUpdated: 0,
            geosetIds: ["4471", "9002"],
            metadata: nil
        )
    }

    /// Deliberately absent from `invocations`: that table asserts the gated-*tail* contract, where
    /// the gate strips detail and leaves the prose identical. The catalog is a different kind of
    /// record — it exists only for diagnostics, so the gate removes it entirely. Emitting bare
    /// "catalogued" lines to every customer's console would be noise, and moving the detail into
    /// the prose to satisfy the table would leak coordinates with the gate off. These tests pin the
    /// same contract the table would have.
    @Test
    func fenceCatalog_expectMachineKeyAndReplayClassification() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogRegion()])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(message.hasPrefix("[Geofence] "))
            #expect(fields["ev"] == "fence.cataloged")
            #expect(fields["io"] == "in")
            for key in ["id", "name", "gs", "lat", "lon", "rad", "tt"] {
                #expect(fields[key] != nil, "missing \(key)= in '\(message)'")
            }
        }
    }

    /// A polygon carries no lat/lon/radius on the wire. Before this, all three were dropped and the
    /// fence catalogued unplaceable — the one thing the catalog exists to prevent.
    @Test
    func fenceCatalog_givenPolygon_expectEnclosingCircleAndRing() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogPolygonRegion()])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["sh"] == "polygon")
            #expect(fields["lat"] == "25.10991")
            #expect(fields["lon"] == "55.18400")
            #expect(fields["rad"] == "625")
            #expect(fields["nv"] == "4")
            // `lat_lon`, the SDK's order — the wire sends `lon,lat`. First vertex is at angle 0,
            // so its longitude is the offset one and its latitude the centre's.
            #expect(fields["ring"]?.hasPrefix("25.10991_55.18550") == true)
        }
    }

    @Test
    func fenceCatalog_givenCircle_expectShapeAndNoRing() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogRegion()])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["sh"] == "circle")
            #expect(fields["rad"] == "150")
            #expect(fields["nv"] == nil)
            #expect(fields["ring"] == nil)
        }
    }

    /// `ring` truncates. `nv` is what lets a consumer notice and refuse, rather than compute
    /// membership against a partial ring that still looks like a valid polygon.
    /// Pins the branch that reads the geometry kernel's own vertex list rather than re-deriving
    /// canonicalisation here. The two only disagree across the antimeridian: the kernel's
    /// `samePosition` unwraps longitude, so a ring closing at +180 that opened at -180 loses its
    /// closing vertex, while an exact comparison keeps it. `nv` is therefore 4 through the kernel
    /// and 5 through the fallback — the one input that tells which path ran.
    /// The mixed-field cases. `carriesPolygonFields` alone made the catalog disagree with the
    /// mapper about what is monitored — the one thing a capture has to get right.
    @Test
    func fenceCatalog_givenMixedFields_expectTheShapeTheMapperMonitors() {
        withDiagnostics(true) {
            func fields(shape: String?, flat: Bool, geometry: Bool) -> [String: String]? {
                let ring: [[Double]] = [[55.1, 25.1], [55.2, 25.1], [55.2, 25.2], [55.1, 25.1]]
                let region = GeofenceApiRegion(
                    id: "mix", name: nil, shape: shape,
                    latitude: flat ? 10.0 : nil, longitude: flat ? 20.0 : nil, radius: flat ? 300 : nil,
                    geometry: geometry ? GeofenceApiGeometry(type: "Polygon", coordinates: [ring]) : nil,
                    enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.15, longitude: 55.15, baseRadiusM: 900),
                    carriesPolygonFields: geometry, externalId: nil,
                    transitionTypes: ["enter"], lastUpdated: 0, geosetIds: nil, metadata: nil
                )
                let logger = CapturingLogger()
                logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.1, regions: [region])
                return parseTail(logger.messages.last ?? "")
            }

            // Explicit circle carrying stray geometry: monitored as a circle, by its flat fields.
            let strayGeometry = fields(shape: "circle", flat: true, geometry: true)
            #expect(strayGeometry?["sh"] == "circle")
            #expect(strayGeometry?["rad"] == "300")

            // Explicit polygon carrying flat fields: monitored by its enclosing circle.
            let flatPolygon = fields(shape: "polygon", flat: true, geometry: true)
            #expect(flatPolygon?["sh"] == "polygon")
            #expect(flatPolygon?["rad"] == "900")

            // Normalization matches the mapper's: padded and mixed case are the same shape.
            #expect(fields(shape: "  Polygon ", flat: false, geometry: true)?["sh"] == "polygon")
            // Blank is not a shape the server named.
            #expect(fields(shape: "   ", flat: true, geometry: false)?["sh"] == "circle")
            // Polygon fields, no discriminator — the mapper drops this; the catalog names it.
            #expect(fields(shape: nil, flat: false, geometry: true)?["sh"] == "undescribed")
            // A shape this version cannot monitor.
            #expect(fields(shape: "hexagon", flat: true, geometry: false)?["sh"] == "unknown")
        }
    }

    @Test
    func fenceCatalog_givenRingClosingAcrossTheAntimeridian_expectTheKernelsRing() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            let ring: [[Double]] = [
                [-180.0, 25.00], [-179.99, 25.00], [-179.99, 25.01], [-180.0, 25.01],
                // Same meridian as the first position, opposite sign.
                [180.0, 25.00]
            ]
            let region = GeofenceApiRegion(
                id: "22251", name: "Antimeridian", shape: "polygon",
                latitude: nil, longitude: nil, radius: nil,
                geometry: GeofenceApiGeometry(type: "Polygon", coordinates: [ring]),
                enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.005, longitude: -179.995, baseRadiusM: 700),
                carriesPolygonFields: true, externalId: nil,
                transitionTypes: ["enter"], lastUpdated: 0, geosetIds: nil, metadata: nil
            )
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [region])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["nv"] == "4", "5 means the fallback ran and kept the wrapped closing vertex")
            #expect(fields["ring"]?.split(separator: ",").count == 4)
        }
    }

    @Test
    func fenceCatalog_givenRingBeyondTheLimit_expectCountStaysAuthoritative() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(
                returnedCount: 1, elapsed: 0.4, regions: [catalogPolygonRegion(vertices: 70)]
            )

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["nv"] == "70")
            #expect(fields["ring"]?.hasSuffix(",+6") == true, "expected a truncation marker in '\(message)'")
        }
    }

    /// The malformed-but-placeable case, and the catalog's whole reason to exist: the ring failed
    /// to decode, so the fence is still worth recording by the circle the OS was given.
    @Test
    func fenceCatalog_givenPolygonWhoseRingDidNotDecode_expectPlaceableWithoutRing() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            var region = catalogPolygonRegion()
            region = GeofenceApiRegion(
                id: region.id, name: region.name, shape: "polygon",
                latitude: nil, longitude: nil, radius: nil,
                geometry: nil,
                enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.109908, longitude: 55.184004, baseRadiusM: 625),
                carriesPolygonFields: true, externalId: nil,
                transitionTypes: ["enter"], lastUpdated: 0, geosetIds: nil, metadata: nil
            )
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [region])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["sh"] == "polygon")
            #expect(fields["lat"] == "25.10991")
            #expect(fields["rad"] == "625")
            #expect(fields["ring"] == nil)
            #expect(fields["nv"] == nil)
        }
    }

    /// A coordinate off the wire is rendered before anything drops invalid regions. `%.5f` on 1e300
    /// is 309 digits, so the record says the server sent garbage instead of carrying it.
    @Test
    func fenceCatalog_givenAbsurdCoordinate_expectItRecordedAsBad() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            let region = GeofenceApiRegion(
                id: "33375", name: nil, shape: "polygon",
                latitude: nil, longitude: nil, radius: nil,
                geometry: GeofenceApiGeometry(type: "Polygon", coordinates: [[[1e300, 25.1], [55.18, 25.11]]]),
                enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.1, longitude: 55.18, baseRadiusM: 400),
                carriesPolygonFields: true, externalId: nil,
                transitionTypes: ["enter"], lastUpdated: 0, geosetIds: nil, metadata: nil
            )
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [region])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["nv"] == "2", "a bad vertex still counts")
            #expect(fields["ring"]?.hasPrefix("25.10000_bad") == true, "got '\(fields["ring"] ?? "")'")
            #expect(message.count < 500, "one absurd coordinate should not blow up the line")
        }
    }

    /// A position with fewer than two coordinates used to be dropped, leaving `nv` counting
    /// vertices the ring never showed — `nv=0` with no ring reads as "polygon with no vertices"
    /// rather than "ring unusable".
    @Test
    func fenceCatalog_givenMalformedPositions_expectCountAndRingAgree() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            let region = GeofenceApiRegion(
                id: "44480", name: nil, shape: "polygon",
                latitude: nil, longitude: nil, radius: nil,
                geometry: GeofenceApiGeometry(type: "Polygon", coordinates: [[[1.0], [2.0]]]),
                enclosingCircle: GeofenceApiEnclosingCircle(latitude: 25.1, longitude: 55.18, baseRadiusM: 400),
                carriesPolygonFields: true, externalId: nil,
                transitionTypes: ["enter"], lastUpdated: 0, geosetIds: nil, metadata: nil
            )
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [region])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            #expect(fields["nv"] == "2")
            #expect(fields["ring"] == "bad_bad,bad_bad")
            // Still placeable by its circle, which is the point of recording it at all.
            #expect(fields["lat"] == "25.10000")
        }
    }

    /// `nv` counts the canonical ring, not the wire ring. A GeoJSON ring closes on itself, so
    /// counting what arrived would report one extra vertex for every polygon — and a consumer
    /// applying "fewer pairs than nv means truncated" would refuse every correct Android polygon.
    /// Agreed with the Android side; both platforms count the unclosed ring.
    @Test
    func fenceCatalog_givenClosedWireRing_expectClosingVertexDropped() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogPolygonRegion(vertices: 4)])

            guard let message = logger.messages.last, let fields = parseTail(message) else {
                Issue.record("no parseable tail in '\(logger.messages.last ?? "<nothing>")'")
                return
            }
            // The wire carried 5 positions; the canonical ring is 4.
            #expect(fields["nv"] == "4")
            #expect(fields["ring"]?.split(separator: ",").count == 4)
        }
    }

    @Test
    func fenceCatalog_givenNameWithSeparators_expectSanitizedButReadable() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(
                returnedCount: 1,
                elapsed: 0.4,
                regions: [catalogRegion(name: "Momo Dubai, Test=1")]
            )
            guard let fields = parseTail(logger.messages.last ?? "") else {
                Issue.record("no parseable tail")
                return
            }
            let name = fields["name"] ?? ""
            #expect(name.contains("Momo"))
            #expect(!name.contains(" "))
            #expect(!name.contains("="))
        }
    }

    @Test
    func fenceCatalog_givenGeosetList_expectSeparatorsPreserved() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogRegion()])
            let fields = parseTail(logger.messages.last ?? "")
            #expect(fields?["gs"] == "4471,9002")
            #expect(fields?["tt"] == "enter,exit")
            #expect(fields?["lat"] == "25.10991")
            #expect(fields?["rad"] == "150")
        }
    }

    @Test
    func fenceCatalog_expectOneRecordPerFence() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(
                returnedCount: 3,
                elapsed: 0.4,
                regions: [catalogRegion(id: "1"), catalogRegion(id: "2"), catalogRegion(id: "3")]
            )
            #expect(logger.messages.filter { $0.contains("ev=fence.cataloged") }.count == 3)
        }
    }

    @Test
    func fenceCatalog_givenDiagnosticsOff_expectNoCatalogRecords() {
        withDiagnostics(false) {
            let logger = CapturingLogger()
            logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [catalogRegion()])
            #expect(!logger.messages.contains { $0.contains("catalogued") })
        }
    }
}
