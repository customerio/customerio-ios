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

        func error(_ message: String, _ tag: String?, _: Error?) {
            record(message, tag)
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
            Invocation(name: "invalidRegionDropped", requiredKeys: ["id", "why"]) { $0.geofenceInvalidRegionDropped("notl core") },
            Invocation(name: "invalidCoordinates", requiredKeys: ["id", "why"]) { $0.geofenceInvalidCoordinatesForRegion("notl_core") },
            Invocation(name: "monitoringFailed", requiredKeys: ["id", "ok"]) { $0.geofenceMonitoringFailed(region: "notl_core", error: GeofenceApiError.transport) },
            Invocation(name: "streamFailed", requiredKeys: ["ok"]) { $0.geofenceMonitorEventStreamFailed(error: GeofenceApiError.transport) },
            Invocation(name: "stoppedMonitoring", requiredKeys: ["id"]) { $0.geofenceMonitorStoppedMonitoringRegion("notl_core") },
            Invocation(name: "regionsRegistered", requiredKeys: ["n", "ids", "mvmt"]) { $0.geofenceRegionsRegistered(identifiers: ["a", "b"], movementTrigger: "cio_movement_trigger") },
            Invocation(name: "permissionUnavailable", requiredKeys: ["perm", "why"]) { $0.geofencePermissionUnavailable(currentStatus: .denied) },
            Invocation(name: "backgroundUnavailable", requiredKeys: ["perm", "why"]) { $0.geofenceBackgroundDeliveryUnavailable(currentStatus: .authorizedWhenInUse) },
            Invocation(name: "backgroundAvailable", requiredKeys: ["perm", "ok"]) { $0.geofenceBackgroundDeliveryAvailable(currentStatus: .authorizedAlways) },
            Invocation(name: "moduleInitialized", requiredKeys: ["launch"]) { $0.geofenceModuleInitialized(launchReason: .appStart) },
            Invocation(name: "moduleWoke", requiredKeys: ["launch"]) { $0.geofenceModuleWoke(launchReason: .locationEvent) },
            Invocation(name: "callbackReceived", requiredKeys: ["id", "t", "buf", "fixsrc", "acc", "age", "sim", "evage"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .enter, fix: location, source: .managerCache, eventDate: Date(timeIntervalSinceNow: -3), buffered: false) },
            Invocation(name: "callbackReceivedNoFix", requiredKeys: ["id", "t", "fixsrc"]) { $0.geofenceCallbackReceived(identifier: "notl_core", transition: .exit, fix: nil, source: .none) },
            Invocation(name: "callbackDropped", requiredKeys: ["id", "t", "why"]) { $0.geofenceCallbackDropped(identifier: "notl_core", transition: .enter, reason: "movement_trigger_not_exit") },
            Invocation(name: "fixReceived", requiredKeys: ["prov"]) { $0.geofenceFixReceived(location, source: "movement_pass") },
            Invocation(name: "fixQuality", requiredKeys: ["fixsrc", "acc", "age"]) { $0.geofenceCallbackReceived(identifier: "q", transition: .enter, fix: location, source: .freshRequest) },
            Invocation(name: "eventTracked", requiredKeys: ["id", "t"]) { $0.geofenceEventTracked(geofenceId: "notl_core", transition: .enter) },
            Invocation(name: "eventSuppressed", requiredKeys: ["id", "t", "why", "cd"]) { $0.geofenceEventSuppressed(geofenceId: "notl_core", transition: .enter, cooldownRemaining: 42) },
            Invocation(name: "droppedAnonymous", requiredKeys: ["id", "t", "why"]) { $0.geofenceTransitionDroppedAnonymous(geofenceId: "notl_core", transition: .exit) },
            Invocation(name: "pendingPersistFailed", requiredKeys: ["id", "t", "ok"]) { $0.geofencePendingPersistFailed(geofenceId: "notl_core", transition: .exit) },
            Invocation(name: "syncSkipped", requiredKeys: ["why"]) { $0.geofenceSyncSkipped(reason: .noIdentifiedUser) },
            Invocation(name: "syncSkippedFresh", requiredKeys: ["why"]) { $0.geofenceSyncSkippedFresh() },
            Invocation(name: "syncFetchFailed", requiredKeys: ["ok", "why"]) { $0.geofenceSyncFetchFailed(error: .http(statusCode: 503)) },
            Invocation(name: "apiFetchResult", requiredKeys: ["ok", "n", "ms"]) { $0.geofenceApiFetchResult(returnedCount: 30, elapsed: 0.42) },
            Invocation(name: "syncCompleted", requiredKeys: ["n", "mvmt", "ms"]) { $0.geofenceSyncCompleted(requestedCount: 19, movementTriggerRequested: true, acceptedCount: 19, movementTriggerAccepted: true, elapsed: 1.5) },
            Invocation(name: "registrationDiff", requiredKeys: ["nadd", "nrem", "nkeep"]) { $0.geofenceRegistrationDiff(added: 3, removed: 2, unchanged: 17) },
            Invocation(name: "rankEvaluated", requiredKeys: ["ncand", "n", "ranked", "evicted"]) { $0.geofenceRankEvaluated(candidates: 30, selectedCount: 2, selected: ["a", "b"], evicted: ["c"], edgeDistances: ["a": 120, "b": 340]) },
            Invocation(name: "movementTrigger", requiredKeys: ["tier"]) { $0.geofenceMovementTrigger(tier: .localRerank) },
            Invocation(name: "movementTriggerRegistered", requiredKeys: ["rad"]) { $0.geofenceMovementTriggerRegistered(latitude: 43.2, longitude: -79.0, radius: 500) },
            Invocation(name: "movementRearmed", requiredKeys: ["why"]) { $0.geofenceMovementRearmedAfterFailedRefresh() },
            Invocation(name: "movementFixResolved", requiredKeys: ["age", "prov"]) { $0.geofenceMovementFixResolved(ageSeconds: 12.5, requested: true) },
            Invocation(name: "movementFixStale", requiredKeys: ["age", "why"]) { $0.geofenceMovementFixStale(ageSeconds: 900) },
            Invocation(name: "movementFixRequestFailed", requiredKeys: ["ok", "why", "ms"]) { $0.geofenceMovementFixRequestFailed(fallingBackToCached: true, elapsed: 5) },
            Invocation(name: "baselineHealed", requiredKeys: ["id", "t"]) { $0.geofenceBaselineHealed(identifier: "notl_core", transition: .enter) },
            Invocation(name: "contradictionRefused", requiredKeys: ["id", "t", "dist", "rad", "edge", "acc"]) { $0.geofenceEventRefusedByContradiction(identifier: "notl_core", transition: .enter, distanceFromCenter: 1400, radius: 1000, accuracy: 48) },
            Invocation(name: "syncSuperseded", requiredKeys: ["why"]) { $0.geofenceSyncSupersededByUserChange() },
            Invocation(name: "resetCompleted", requiredKeys: ["ok"]) { $0.geofenceResetCompleted() },
            Invocation(name: "resetSuperseded", requiredKeys: ["ok", "why"]) { $0.geofenceResetSuperseded() },
            Invocation(name: "firstRunRearm", requiredKeys: ["why"]) { $0.geofenceFirstRunRearm() },
            Invocation(name: "regionsAdopted", requiredKeys: ["n"]) { $0.geofenceRegionsAdopted(count: 4) },
            Invocation(name: "foregroundRearm", requiredKeys: ["n", "why"]) { $0.geofenceForegroundRearm(count: 4) },
            Invocation(name: "storageLoaded", requiredKeys: ["n", "anchor"]) { $0.geofenceStorageLoaded(regionCount: 30, hasAnchor: true) }
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
        let previous = GeofenceDiagnostics.overrideForTesting
        GeofenceDiagnostics.overrideForTesting = enabled
        defer { GeofenceDiagnostics.overrideForTesting = previous }
        return try body()
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
                #expect(fields["ev"] != nil, "\(invocation.name): missing ev=")
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
        GeofenceDiagnostics.overrideForTesting = true
        defer { GeofenceDiagnostics.overrideForTesting = nil }
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
            logger.geofenceEventTracked(geofenceId: "niagara on the lake", transition: .enter)

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
        GeofenceDiagnostics.overrideForTesting = true
        defer { GeofenceDiagnostics.overrideForTesting = nil }
        for raw in ["store,north", "a=b", "aisle:3", "wing|west"] {
            let logger = CapturingLogger()
            logger.geofenceEventTracked(geofenceId: raw, transition: .enter)
            let tail = parseTail(logger.messages.last ?? "")
            #expect(tail?["id"] != nil, "no id for \(raw)")
            let id = tail?["id"] ?? ""
            #expect(!id.contains(where: { "=,:|".contains($0) }), "id kept a separator: \(id)")
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
}
