@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// Producer side of the diagnostics tail. The parser is off-device with no round trip here, so a
/// renamed key would otherwise go unnoticed.
@Suite("Geofence log tail", .serialized)
struct GeofenceLogTailTests {
    // MARK: - Test double

    private func parseTail(_ message: String) -> [String: String]? {
        GeofenceTail.parse(message)
    }

    /// Hand-enumerated (Swift can't reflect over extension methods): a new logger method needs a row.
    private struct Invocation {
        let name: String
        /// Pinned per row: a set can't see two records swapping keys.
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
            Invocation(name: "callbackReceived", ev: "os.callback.received", requiredKeys: ["id", "t", "buf", "fixsrc", "acc", "age", "sim", "evage", "edate"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .enter, fix: location, source: .managerCache, eventDate: Date(timeIntervalSinceNow: -3), buffered: false, now: Date()) },
            Invocation(name: "callbackReceivedNoFix", ev: "os.callback.received", requiredKeys: ["id", "t", "fixsrc"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .exit, fix: nil, source: .none, now: Date()) },
            Invocation(name: "info", ev: "info", requiredKeys: ["why"]) { $0.geofenceInfo("os_state_unusable", fields: [("id", "notl_core"), ("state", "unknown")]) },
            Invocation(name: "callbackDropped", ev: "os.callback.dropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceCallbackDropped(identifier: "notl_core", transition: .enter, reason: "movement_trigger_not_exit") },
            Invocation(name: "fixReceived", ev: "fix.received", requiredKeys: ["prov", "lat", "lon", "acc", "age"]) { $0.geofenceFixReceived(location, source: "movement_pass", now: Date()) },
            Invocation(name: "locationFix", ev: "location.fix", requiredKeys: ["lat", "lon", "acc", "age", "prov"]) { $0.geofenceLocationFix(location, source: .managerCache, now: Date()) },
            Invocation(name: "identityChanged", ev: "identity.changed", requiredKeys: ["ok"]) { $0.geofenceIdentityChanged(identified: true) },
            Invocation(name: "fixQuality", ev: "os.callback.received", requiredKeys: ["fixsrc", "acc", "age"]) { $0.geofenceCallbackReceived(identifier: "q", transition: .enter, fix: location, source: .freshRequest, now: Date()) },
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
            Invocation(name: "conditionAdded", ev: "condition.added", requiredKeys: ["id"]) { $0.geofenceConditionAdded(identifier: "notl_core") },
            Invocation(name: "conditionRemovedForReadd", ev: "condition.removed", requiredKeys: ["id", "op"]) { $0.geofenceConditionRemoved(identifier: "notl_core", op: .readd) },
            Invocation(name: "conditionRemovedForDrop", ev: "condition.removed", requiredKeys: ["id", "op"]) { $0.geofenceConditionRemoved(identifier: "notl_core", op: .drop) },
            Invocation(name: "rankEvaluated", ev: "rank.evaluated", requiredKeys: ["ncand", "n", "ranked", "evicted"]) { $0.geofenceRankEvaluated(candidates: 30, selectedCount: 2, selected: ["a", "b"], evicted: ["c"], edgeDistances: ["a": 120, "b": 340]) },
            Invocation(name: "movementTrigger", ev: "movement.exit", requiredKeys: ["tier"]) { $0.geofenceMovementTrigger(tier: .localRerank) },
            Invocation(name: "movementTriggerRegistered", ev: "movement.registered", requiredKeys: ["rad"]) { $0.geofenceMovementTriggerRegistered(latitude: 43.2, longitude: -79.0, radius: 500) },
            Invocation(name: "movementRearmed", ev: "movement.rearmed", requiredKeys: ["why"]) { $0.geofenceMovementRearmedAfterFailedRefresh() },
            Invocation(name: "allRegionsDropped", ev: "api.fetch.unreadable", requiredKeys: ["ok", "n", "why"]) { $0.geofenceAllRegionsDropped(count: 4) },
            Invocation(name: "callbackDispatched", ev: "os.callback.dispatched", requiredKeys: ["id", "t"]) { $0.geofenceCallbackDispatched(identifier: "notl_core", transition: .enter) },
            Invocation(name: "polygonTransition", ev: "polygon.transition", requiredKeys: ["id", "t", "by"]) { $0.geofencePolygonTransition(identifier: "notl_core", transition: .enter, confirmedByFix: true) },
            Invocation(name: "polygonPassSkipped", ev: "polygon.pass.skipped", requiredKeys: ["why"]) { $0.geofencePolygonPassSkipped(reason: .passInFlight) },
            Invocation(name: "polygonPassStarted", ev: "polygon.pass.started", requiredKeys: ["why", "n", "pass"]) { $0.geofencePolygonPassStarted(reason: .foreground, count: 3, pass: 7) },
            Invocation(name: "polygonEvaluationRequested", ev: "polygon.evaluation.requested", requiredKeys: ["id", "why"]) { $0.geofencePolygonEvaluationRequested(identifier: "notl_core", reason: .newPolygon) },
            Invocation(name: "polygonDropped", ev: "registration.rejected", requiredKeys: ["id", "why", "rad", "lim"]) { $0.geofencePolygonExceedsMonitoringLimit(identifier: "notl_core", radius: 12000, limit: 10000) },
            Invocation(name: "polygonWakePass", ev: "polygon.wake.pass", requiredKeys: ["rad", "n"]) { $0.geofencePolygonWakePass(radius: 420, polygonCount: 3) },
            Invocation(name: "polygonVerdict", ev: "polygon.verdict", requiredKeys: ["id", "m", "edge", "acc", "age", "pass", "cor"]) { $0.geofencePolygonVerdict(identifier: "notl_core", verdict: PolygonVerdict(membership: .inside, corroboration: .notNeeded, signedEdgeDistance: 80, pass: 7), horizontalAccuracy: 12, fixAge: 3.5) },
            Invocation(name: "polygonVerdictUnconfirmed", ev: "polygon.verdict", requiredKeys: ["id", "m", "pass", "cor", "corwhy"]) { $0.geofencePolygonVerdict(identifier: "notl_core", verdict: PolygonVerdict(membership: .inside, corroboration: .unconfirmed(.noUsableFix), signedEdgeDistance: 3, pass: 2), horizontalAccuracy: 5, fixAge: 1) },
            Invocation(name: "polygonUndelivered", ev: "polygon.undelivered", requiredKeys: ["id", "why"]) { $0.geofencePolygonNotDelivered(identifier: "notl_core", reason: .outcome(.suppressedInitialOutside)) },
            Invocation(name: "polygonUndecided", ev: "polygon.undecided", requiredKeys: ["id", "why", "edge", "acc", "pass"]) { $0.geofencePolygonUndecided(identifier: "notl_core", reason: .withinAccuracy, signedEdgeDistance: -4, horizontalAccuracy: 12, pass: 7) },
            Invocation(name: "wakeRadiusChosen", ev: "movement.radius.chosen", requiredKeys: ["rad", "from"]) { $0.geofenceWakeRadiusChosen(radius: 640, anchorIsLiveFix: true) },
            Invocation(name: "movementFixResolved", ev: "movement.fix.resolved", requiredKeys: ["age", "prov", "spd", "for"]) { $0.geofenceMovementFixResolved(ageSeconds: 12.5, requested: true, speed: 13.4, purpose: .movement) },
            Invocation(name: "movementFixStale", ev: "movement.fix.requested", requiredKeys: ["age", "why"]) { $0.geofenceMovementFixStale(ageSeconds: 900) },
            Invocation(name: "movementFixRequestFailed", ev: "movement.fix.failed", requiredKeys: ["ok", "why", "ms"]) { $0.geofenceMovementFixRequestFailed(fallingBackToCached: true, elapsed: 5) },
            Invocation(name: "baselineHealed", ev: "baseline.healed", requiredKeys: ["id", "t"]) { $0.geofenceBaselineHealed(identifier: "notl_core", transition: .enter) },
            Invocation(name: "contradictionEvaluated", ev: "contradiction.evaluated", requiredKeys: ["id", "t", "dly", "win"]) { $0.geofenceContradictionEvaluated(identifier: "notl_core", transition: .enter, delaySinceAdd: 1.25, insideWindow: true) },
            Invocation(name: "contradictionRefused", ev: "contradiction.refused", requiredKeys: ["id", "t", "dist", "rad", "edge", "acc"]) { $0.geofenceEventRefusedByContradiction(identifier: "notl_core", transition: .enter, distanceFromCenter: 1400, radius: 1000, accuracy: 48) },
            Invocation(name: "contradictionAllowed", ev: "contradiction.allowed", requiredKeys: ["id", "t", "dist", "rad", "edge", "acc", "age"]) { $0.geofenceContradictionAllowed(identifier: "notl_core", transition: .enter, geometry: GateFixGeometry(distanceFromCenter: 980, radius: 1000, accuracy: 48, fixAge: 3.5)) },
            Invocation(name: "contradictionNoFix", ev: "contradiction.no_fix", requiredKeys: ["id", "t", "why"]) { $0.geofenceContradictionNoFix(identifier: "notl_core", transition: .exit, reason: .noFixAvailable) },
            Invocation(name: "syncSuperseded", ev: "sync.superseded", requiredKeys: ["why"]) { $0.geofenceSyncSupersededByUserChange() },
            Invocation(name: "locationArrived", ev: "location.fix", requiredKeys: ["lat", "lon", "prov"]) { $0.geofenceLocationArrived(LocationData(latitude: 43.2, longitude: -79.0)) },
            Invocation(name: "resetCompleted", ev: "module.reset", requiredKeys: ["ok"]) { $0.geofenceResetCompleted() },
            Invocation(name: "resetSuperseded", ev: "module.reset", requiredKeys: ["ok", "why"]) { $0.geofenceResetSuperseded() },
            Invocation(name: "firstRunRearm", ev: "movement.rearmed", requiredKeys: ["why"]) { $0.geofenceFirstRunRearm() },
            Invocation(name: "regionsAdopted", ev: "registration.adopted", requiredKeys: ["n", "ids"]) { $0.geofenceRegionsAdopted(identifiers: ["a", "b", "c", "d"]) },
            Invocation(name: "foregroundRearm", ev: "registration.rearmed", requiredKeys: ["n", "why"]) { $0.geofenceForegroundRearm(count: 4) },
            Invocation(name: "storageLoaded", ev: "storage.loaded", requiredKeys: ["n", "anchor"]) { $0.geofenceStorageLoaded(regionCount: 30, hasAnchor: true) },
            Invocation(name: "queueRowsDropped", ev: "queue.rows_dropped", requiredKeys: ["why", "n", "total"]) { $0.geofenceQueueRowsDropped(count: 1, of: 3) },
            Invocation(name: "queueUnreadable", ev: "queue.unreadable", requiredKeys: ["why"]) { $0.geofenceQueueUnreadable(reason: .readFailed) },
            Invocation(name: "droppedQueueUnreadable", ev: "transition.dropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceTransitionDroppedQueueUnreadable(geofenceId: "notl_core", transition: .enter) },
            Invocation(name: "visitMonitoringStarted", ev: "visit.monitoring", requiredKeys: ["state"]) { $0.geofenceVisitMonitoringStarted() },
            Invocation(name: "visitMonitoringStopped", ev: "visit.monitoring", requiredKeys: ["state"]) { $0.geofenceVisitMonitoringStopped() },
            Invocation(name: "visitMonitoringSkipped", ev: "visit.monitoring", requiredKeys: ["state", "why", "status"]) { $0.geofenceVisitMonitoringSkipped(status: CLAuthorizationStatus.authorizedWhenInUse.rawValue) },
            Invocation(name: "visitReported", ev: "visit.reported", requiredKeys: ["edge", "lat", "lon", "acc", "delay"]) { $0.geofenceVisitReported(coordinate: LocationData(latitude: 25.1, longitude: 55.2), isArrival: true, horizontalAccuracy: 30, reportDelay: 960) }
        ]
    }

    private func runAll(_ logger: Logger) {
        for invocation in invocations {
            invocation.run(logger)
        }
    }

    // MARK: - Contract

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
                let expectedIo = Self.declaredIo[invocation.ev] ?? "obs"
                #expect(
                    fields["io"] == expectedIo,
                    "\(invocation.name): ev=\(invocation.ev) is declared io=\(expectedIo), emitted io=\(fields["io"] ?? "<absent>")"
                )
                for key in invocation.requiredKeys {
                    #expect(fields[key] != nil, "\(invocation.name): missing \(key)= in '\(message)'")
                }
            }
        }
    }

    @Test
    func movementFixResolved_expectTheAskingDecisionNamed() {
        withDiagnostics(true) {
            for purpose in [GeofenceFixPurpose.movement, .contradictionGate, .baselineHeal, .pendingEvents, .polygon] {
                let logger = CapturingLogger()
                logger.geofenceMovementFixResolved(ageSeconds: 1, requested: false, speed: 5, purpose: purpose)
                #expect(parseTail(logger.messages.last ?? "")?["for"] == purpose.rawValue)
            }
            #expect(Set([GeofenceFixPurpose.movement, .contradictionGate, .baselineHeal, .pendingEvents, .polygon].map(\.rawValue)).count == 5)
        }
    }

    /// CoreLocation's -1 means "no speed", not stationary.
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
        let errors: [BackgroundDeliveryHttpError] = [
            .missingApiHost, .missingCdpApiKey, .invalidRequest, .transport,
            .http(statusCode: 401), .http(statusCode: 503)
        ]
        let tokens = errors.map(\.diagnosticReason)
        #expect(Set(tokens).count == tokens.count, "two causes share a token: \(tokens)")
        #expect(tokens.allSatisfy { !$0.contains(" ") }, "a reason token contains whitespace")
        // 0 means no response at all, not a status the backend sent.
        #expect(BackgroundDeliveryHttpError.http(statusCode: 0).diagnosticReason == "no_response")
        #expect(BackgroundDeliveryHttpError.http(statusCode: 503).diagnosticReason == "http_503")
    }

    /// Absent means `obs`. Keys shared with Android must keep the `io` its `GeofenceLogTailTest`
    /// asserts.
    private static let declaredIo: [String: String] = [
        "api.fetch.result": "in",
        "visit.reported": "in",
        // Reads, so `in`: an unparseable catalogue and the two pending-queue reads.
        "api.fetch.unreadable": "in",
        "queue.rows_dropped": "in",
        "queue.unreadable": "in",
        "fence.cataloged": "in",
        "identity.changed": "in",
        "location.fix": "in",
        "module.init": "in",
        "module.wake": "in",
        "os.callback.received": "in",
        "os.monitor.failed": "in",
        "os.monitor.stopped": "in",
        "os.stream.failed": "in",
        "permission.changed": "in",
        "contradiction.refused": "obs",
        "module.reset": "out",
        "os.callback.dropped": "obs",
        "registration.applied": "out",
        "transition.accepted": "out",
        "transition.dropped": "obs",
        "transition.suppressed": "obs",
        "transition.synthesized": "obs"
    ]

    /// The outputs: decisions that cross back out of the SDK. Decisions about inputs are `obs`.
    private static let frozenOutputs: Set<String> = [
        "module.reset",
        "registration.applied",
        "transition.accepted"
    ]

    /// Reads what the logger emitted, not `declaredIo`, so a mistake in the map cannot validate itself.
    @Test
    func assertionSurface_expectExactlyTheFrozenOutputs() {
        GeofenceDiagnostics.$overrideForTesting.withValue(true) {
            var emitted: Set<String> = []
            for invocation in invocations {
                let logger = CapturingLogger()
                invocation.run(logger)
                guard let message = logger.messages.last, let fields = parseTail(message) else { continue }
                if fields["io"] == "out" { emitted.insert(fields["ev"] ?? invocation.ev) }
            }
            #expect(emitted == Self.frozenOutputs, "assertion surface drifted: \(emitted.symmetricDifference(Self.frozenOutputs).sorted())")
        }
    }

    private static let declaredVocabulary: Set<String> = [
        "visit.monitoring",
        "visit.reported",
        "api.fetch.result",
        "api.fetch.unreadable",
        "baseline.healed",
        "baseline.refused",
        "condition.added",
        "condition.removed",
        "contradiction.allowed",
        "contradiction.evaluated",
        "contradiction.no_fix",
        "contradiction.refused",
        "delivery.failed",
        "delivery.queued",
        "delivery.sent",
        "fix.received",
        "identity.changed",
        "info",
        "location.fix",
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
        "polygon.pass.started",
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
    /// The table only checks `why=` is present, so only this catches two cases swapping tokens.
    @Test
    func regionDropReason_expectDistinctPinnedTokenPerCause() {
        let cases = GeofenceRegionDropReason.allCases
        for reason in cases {
            switch reason {
            case .unknownShape: #expect(reason.logToken == "unknown_shape")
            case .undescribedShape: #expect(reason.logToken == "undescribed_shape")
            case .unusableCircle: #expect(reason.logToken == "unusable_circle")
            case .unusablePolygon: #expect(reason.logToken == "unusable_polygon")
            }
        }
        expectUsableTokens(cases.map(\.logToken))
    }

    @Test
    func polygonOutcome_expectDistinctPinnedTokenPerCause() {
        let cases: [PolygonMembershipOutcome] = [
            .deliver(.enter), .discoveredInside, .suppressedNoChange, .suppressedNewerDecision,
            .suppressedInitialOutside, .suppressedUnmonitored, .suppressedGeometryChanged
        ]
        for outcome in cases {
            switch outcome {
            case .deliver: #expect(outcome.logToken == "deliver")
            case .discoveredInside: #expect(outcome.logToken == "discovered_inside")
            case .suppressedNoChange: #expect(outcome.logToken == "no_change")
            case .suppressedNewerDecision: #expect(outcome.logToken == "newer_decision")
            case .suppressedInitialOutside: #expect(outcome.logToken == "initial_outside")
            case .suppressedUnmonitored: #expect(outcome.logToken == "unmonitored")
            case .suppressedGeometryChanged: #expect(outcome.logToken == "geometry_changed")
            }
        }
        expectUsableTokens(cases.map(\.logToken))
    }

    /// Reusing `no_change` for either refusal would report a refused delivery as one never owed.
    @Test
    func polygonUndeliveredReason_expectRefusalsDistinctFromOutcomes() {
        let outcomes: [PolygonMembershipOutcome] = [
            .deliver(.enter), .discoveredInside, .suppressedNoChange, .suppressedNewerDecision,
            .suppressedInitialOutside, .suppressedUnmonitored, .suppressedGeometryChanged
        ]
        let cases: [PolygonUndeliveredReason] = outcomes.map { .outcome($0) } + [.userChanged, .transitionNotRegistered]
        for reason in cases {
            switch reason {
            case .outcome(let outcome): #expect(reason.logToken == outcome.logToken)
            case .userChanged: #expect(reason.logToken == "user_changed")
            case .transitionNotRegistered: #expect(reason.logToken == "transition_type_not_registered")
            }
        }
        expectUsableTokens(cases.map(\.logToken))
    }

    @Test
    func monitorEventOutcome_expectDistinctPinnedTokenPerCause() {
        for outcome in GeofenceMonitorEventOutcome.allCases {
            switch outcome {
            case .deliver: #expect(outcome.diagnosticReason == nil, "deliver is not a discard and must log nothing")
            case .suppressedNoChange: #expect(outcome.diagnosticReason == "no_state_change")
            case .suppressedFilteredType: #expect(outcome.diagnosticReason == "transition_type_not_registered")
            case .suppressedNoBaseline: #expect(outcome.diagnosticReason == "baseline_established")
            case .suppressedNewerBaseline: #expect(outcome.diagnosticReason == "newer_baseline")
            case .suppressedRedelivery: #expect(outcome.diagnosticReason == "redelivered")
            case .suppressedPredatesRegistration: #expect(outcome.diagnosticReason == "predates_registration")
            }
        }
        expectUsableTokens(GeofenceMonitorEventOutcome.allCases.compactMap(\.diagnosticReason))
    }

    @Test
    func apiError_expectDistinctPinnedTokenPerCause() {
        let cases: [GeofenceApiError] = [
            .missingApiHost, .missingCdpApiKey, .invalidRequest, .http(statusCode: 503), .transport, .decoding
        ]
        for error in cases {
            switch error {
            case .missingApiHost: #expect(error.diagnosticToken == "missing_api_host")
            case .missingCdpApiKey: #expect(error.diagnosticToken == "missing_cdp_api_key")
            case .invalidRequest: #expect(error.diagnosticToken == "invalid_request")
            case .http(let statusCode): #expect(error.diagnosticToken == "http_\(statusCode)")
            case .transport: #expect(error.diagnosticToken == "transport")
            case .decoding: #expect(error.diagnosticToken == "decoding")
            }
        }
        #expect(GeofenceApiError.http(statusCode: 401).diagnosticToken == "http_401")
        #expect(GeofenceApiError.http(statusCode: 503).diagnosticToken == "http_503")
        expectUsableTokens(cases.map(\.diagnosticToken))
    }

    @Test
    func permissionToken_expectDistinctPinnedTokenPerStatus() {
        let statuses: [CLAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways, .authorizedWhenInUse]
        for status in statuses {
            switch status {
            case .notDetermined: #expect(GeofenceLog.permission(status) == "not_determined")
            case .restricted: #expect(GeofenceLog.permission(status) == "restricted")
            case .denied: #expect(GeofenceLog.permission(status) == "denied")
            case .authorizedAlways: #expect(GeofenceLog.permission(status) == "always")
            case .authorizedWhenInUse: #expect(GeofenceLog.permission(status) == "when_in_use")
            @unknown default: Issue.record("unhandled CLAuthorizationStatus in the test table")
            }
        }
        expectUsableTokens(statuses.map(GeofenceLog.permission))
    }

    /// Token assertions read this set from production, so narrowing it would silently relax them.
    @Test
    func separators_expectThePinnedSet() {
        #expect(GeofenceLog.separators == ["=", ",", ":", "|"])
    }

    /// A case without an explicit raw value uses its Swift name, so a rename changes the wire token.
    @Test
    func rawValueTokens_expectThePinnedSetPerEnum() {
        // Also the tracked event's `transition`, persisted pending rows, and the pending/cooldown keys.
        expectTokens(GeofenceTransition.self, ["enter", "dwell", "exit"])
        // camelCase on purpose: Android emits neither.
        expectTokens(HandleMovementTier.self, ["localRerank", "remoteRefresh"])
        expectTokens(PolygonPassSkipReason.self, ["pass_in_flight"])
        expectTokens(PolygonEvaluationReason.self, ["new_polygon", "new_polygon_forced_request_failed", "movement", "foreground",
                                                    "os_transition", "visit"])
        expectTokens(PolygonUndecidedReason.self, [
            "no_usable_fix", "user_changed", "ring_unbuildable", "unregistered", "circle_expired",
            "within_accuracy", "fix_too_old", "accuracy_too_low", "corroboration_unnecessary",
            "corroboration_disagreed", "corroboration_not_independent"
        ])
        // The formatter strips a raw value matching the case name, so this pin is all that holds
        // `none`, `reused` and `newer`.
        expectTokens(PolygonMembershipResolver.HeldFixUse.self, ["none", "reused", "too_old", "newer"])
        expectTokens(GeofenceFixPurpose.self, ["movement", "gate", "heal", "pending", "polygon"])
        expectTokens(GeofenceCatalogShape.self, ["circle", "polygon", "undescribed", "unknown"])
        expectTokens(GeofenceLog.FixSource.self, ["manager_cache", "resolver", "fresh_request", "gate", "bus", "synthetic", "none"])
    }

    private func expectTokens<T: RawRepresentable & CaseIterable>(
        _: T.Type,
        _ expected: Set<String>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) where T.RawValue == String {
        let actual = Set(T.allCases.map(\.rawValue))
        #expect(actual == expected, "\(T.self) tokens changed: \(actual.symmetricDifference(expected))", sourceLocation: sourceLocation)
        expectUsableTokens(Array(actual), sourceLocation: sourceLocation)
    }

    private func expectUsableTokens(_ tokens: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(tokens).count == tokens.count, "two causes share a token: \(tokens)", sourceLocation: sourceLocation)
        #expect(tokens.allSatisfy { !$0.isEmpty }, "a reason token is empty", sourceLocation: sourceLocation)
        for token in tokens {
            #expect(
                !token.contains(where: { $0.isWhitespace || GeofenceLog.separators.contains($0) }),
                "token '\(token)' holds whitespace or a tail separator",
                sourceLocation: sourceLocation
            )
        }
    }

    /// `contradiction.allowed` keeps the edge's sign (negative inside); `contradiction.refused` floors
    /// it at zero. Asserted from position, so an inverted "inside" fails.
    @Test
    func contradictionAllowed_givenAFixInsideTheFence_expectANegativeEdgeMatchingTheDecision() {
        let radius: Double = 1000
        // Not 980: that edge equals `baselineHealMinEdgeMargin`, and the rule needs
        // `abs(edge) > margin`.
        let insideDistance: Double = 900
        let geometry = GateFixGeometry(
            distanceFromCenter: insideDistance, radius: radius, accuracy: 48, fixAge: 3.5
        )
        let logger = CapturingLogger()
        withDiagnostics(true) {
            logger.geofenceContradictionAllowed(
                identifier: "notl_core", transition: .enter, geometry: geometry
            )
        }
        let tail = parseTail(logger.messages.last ?? "")

        #expect(BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: insideDistance, radius: radius,
            horizontalAccuracy: 5, fixAge: 1, lastState: .exit
        ) == .enter, "fixture is not physically inside by the gate's own rule")
        #expect(geometry.signedEdgeDistance < 0, "circle convention: negative inside")
        #expect(tail?["edge"] == "-100", "edge lost its sign: \(String(describing: tail?["edge"]))")
        #expect(tail?["age"] == "3.5")
        #expect(tail?["acc"] == "48.0")
    }

    @Test
    func everyRecord_expectTheDeclaredVocabulary() {
        // `seen` comes from the table, so a record missing from it goes unnoticed. `fence.cataloged`
        // has no row (a private helper emits it); `fenceCatalog_...` asserts its `ev`.
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

                // Prose only, not "safe fields only", so a new tail field never needs its own
                // privacy review.
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

    /// `cor` stays `true`/`false` as on Android; the reason goes in iOS-only `corwhy`, absent when
    /// decisive.
    @Test
    func verdictCorroboration_expectCorStaysBooleanAndTheReasonRidesSeparately() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofencePolygonVerdict(
                identifier: "notl_core",
                verdict: PolygonVerdict(
                    membership: .inside, corroboration: .unconfirmed(.noUsableFix),
                    signedEdgeDistance: 3, pass: 1
                ),
                horizontalAccuracy: 5, fixAge: 1
            )
            let unconfirmed = logger.messages.last ?? ""
            #expect(unconfirmed.contains("cor=false"), "cor must stay boolean: \(unconfirmed)")
            #expect(unconfirmed.contains("corwhy=no_usable_fix"), "reason missing: \(unconfirmed)")

            logger.geofencePolygonVerdict(
                identifier: "notl_core",
                verdict: PolygonVerdict(
                    membership: .inside, corroboration: .confirmed,
                    signedEdgeDistance: 80, pass: 1
                ),
                horizontalAccuracy: 5, fixAge: 1
            )
            let confirmed = logger.messages.last ?? ""
            #expect(confirmed.contains("cor=true"), "confirmed must read true: \(confirmed)")
            #expect(!confirmed.contains("corwhy="), "corwhy must be absent: \(confirmed)")
        }
    }

    @Test
    func listValues_expectSeparatorsSurviveTheTailBuilder() {
        // `sanitize` must not fold a deliberately composed list (`ids=a,b` would become `ids=a_b`).
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
    func conditionMirror_expectAnAbsentFieldLeavesNoKeyBehind() {
        // A key printed with an empty value would read in a capture as a measured zero.
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceInfo("condition_mirror", fields: [
                ("at", "poll"),
                ("want", "13"),
                ("missing", nil),
                ("extra", nil)
            ])
            let message = logger.messages.last ?? ""
            #expect(message.contains("want=13"), "lost a field it should keep: \(message)")
            #expect(!message.contains("missing="), "nil field left a key behind: \(message)")
            #expect(!message.contains("extra="), "nil field left a key behind: \(message)")
        }
    }

    @Test
    func conditionMirror_expectIdentifierListsKeepTheirSeparators() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            logger.geofenceInfo("condition_mirror", fields: [
                ("os", "12"),
                ("owned", "13"),
                ("missing", GeofenceLog.list(["alpha", "beta"])),
                ("extra", GeofenceLog.list(["gamma"]))
            ])
            let message = logger.messages.last ?? ""
            #expect(message.contains("missing=alpha,beta"), "missing lost its separators: \(message)")
            #expect(message.contains("extra=gamma"), "extra malformed: \(message)")
        }
    }

    @Test
    func proseHalf_expectIdenticalWhicheverWayTheGateIsSet() {
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
        // `tail` folds whitespace in every value, so only this covers the format's own separators.
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
        // Every other test asserts on output, so an eager shim would pass them all.
        var builds = 0
        let fields: () -> [(String, String?)] = {
            builds += 1
            return [("lat", "37.45000"), ("lon", "-122.08400")]
        }

        withDiagnostics(false) {
            #expect(GeofenceLog.tail("probe", .output, fields()).isEmpty)
            #expect(builds == 0, "GeofenceLog.tail evaluated its fields with the gate off")

            // The shim re-wraps the autoclosure, which is easy to lose in a refactor.
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

    /// GeoJSON order (longitude first) and CLOSED, as on the wire.
    private func catalogPolygonRegion(id: String = "22250", vertices: Int = 4) -> GeofenceApiRegion {
        // Not collinear: the kernel would reject it and every assertion would silently hit the
        // fallback.
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

    /// Not in `invocations`: the gate removes the catalog entirely, prose included.
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

    /// A polygon carries no lat/lon/radius on the wire; all three come from the enclosing circle.
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
            // `lat_lon`, though the wire sends `lon,lat`. Vertex 0 is at angle 0: centre latitude,
            // offset longitude.
            #expect(fields["ring"]?.hasPrefix("25.10991_55.18550") == true)
        }
    }

    @Test
    func fenceCatalog_givenDwellThreshold_expectRawValueOrOmittedWhenMissing() {
        withDiagnostics(true) {
            for threshold in [nil, 0, 60, -1, Int.max] as [Int?] {
                for var region in [catalogRegion(), catalogPolygonRegion()] {
                    region.dwellThresholdSeconds = threshold
                    let logger = CapturingLogger()
                    logger.geofenceApiFetchResult(returnedCount: 1, elapsed: 0.4, regions: [region])
                    guard let fields = parseTail(logger.messages.last ?? "") else {
                        Issue.record("missing catalogue tail for threshold \(String(describing: threshold))")
                        continue
                    }
                    #expect(fields["ev"] == "fence.cataloged")
                    #expect(fields["dwell"] == threshold.map(String.init))
                }
            }
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

    /// The shape the mapper monitors, not just `carriesPolygonFields`.
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

            // Normalized like the mapper: padding and case are ignored.
            #expect(fields(shape: "  Polygon ", flat: false, geometry: true)?["sh"] == "polygon")
            // Blank is not a shape the server named.
            #expect(fields(shape: "   ", flat: true, geometry: false)?["sh"] == "circle")
            // Polygon fields, no discriminator — the mapper drops this; the catalog names it.
            #expect(fields(shape: nil, flat: false, geometry: true)?["sh"] == "undescribed")
            // A shape this version cannot monitor.
            #expect(fields(shape: "hexagon", flat: true, geometry: false)?["sh"] == "unknown")
        }
    }

    /// The kernel unwraps longitude, so its ring drops the +180 closing vertex (`nv` 4); the fallback
    /// keeps it (`nv` 5).
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

    /// `ring` truncates; `nv` stays the full count so a consumer can refuse a partial ring.
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

    /// Rendered before invalid regions are dropped; `%.5f` on 1e300 would be 309 digits.
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

    /// Rendered as `bad_bad`, not dropped, so `nv` matches the pairs in `ring`.
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
            #expect(fields["lat"] == "25.10000")
        }
    }

    /// Both platforms count the unclosed ring; counting the wire's closing vertex would read as
    /// truncation.
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
