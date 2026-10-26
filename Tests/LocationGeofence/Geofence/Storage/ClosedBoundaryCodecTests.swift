@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// The closure date a monitor EXIT stamps on a visit is read back from the state file exactly, bit
/// for bit: the visit's own EXIT is recognised by date equality, and a different EXIT in the same
/// millisecond must not be. Each test stamps through the producer write
/// (`recordMonitorTransition` with a clock reading) into a real `GeofenceStorage` file and reads it
/// back through the same storage, which decodes the file on every read.
@Suite("ClosedBoundaryCodec", .serialized)
struct ClosedBoundaryCodecTests {
    private static let circle = DurableExitFences.circle

    /// Reference-date intervals: an ordinary fraction, one bit above a whole second, and a value
    /// the old seconds-since-1970 encoding happened to keep.
    @Test(arguments: [810907800.1, 810907800.0.nextUp, 810907800.1234567])
    func stampedClosure_expectReadBackExactly(interval: TimeInterval) async throws {
        let exitedAt = Date(timeIntervalSinceReferenceDate: interval)
        let store = await Store(enteringBefore: exitedAt)
        _ = try await store.saveVisit()
        try await store.recordExit(at: exitedAt)

        let closed = try #require(await store.visit()?.closedByObservedBoundary)
        #expect(closed == exitedAt)
        #expect(closed.timeIntervalSinceReferenceDate.bitPattern == interval.bitPattern)
        // A different EXIT two microseconds later, in the same millisecond, is not this one.
        let sameMillisecond = Date(timeIntervalSinceReferenceDate: interval + 0.000002)
        #expect(Int64((sameMillisecond.timeIntervalSince1970 * 1000).rounded(.down)) == Int64((exitedAt.timeIntervalSince1970 * 1000).rounded(.down)))
        #expect(closed != sameMillisecond)
    }

    /// Control: the closure leaves a reservation exactly as it was.
    @Test
    func stampedReservedVisit_expectTheReservationUnchanged() async throws {
        let exitedAt = Date(timeIntervalSinceReferenceDate: 810907800.1)
        let store = await Store(enteringBefore: exitedAt)
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: 1789215000123, enteredAtEpochMilliseconds: 1789214400123, durationSeconds: 600,
            thresholdSeconds: 600, detectionSource: "location_evidence"
        )
        _ = try await store.saveVisit(reservation: reservation)
        try await store.recordExit(at: exitedAt)

        let visit = try #require(await store.visit())
        #expect(visit.dwellReservation == reservation)
        #expect(visit.closedByObservedBoundary == exitedAt)
    }

    /// Control: a visit never closed writes no closure key and reads back unclosed.
    @Test
    func unclosedVisit_expectNoKeyAndNoClosure() async throws {
        let store = await Store(enteringBefore: Date(timeIntervalSinceReferenceDate: 810907800.1))
        let saved = try await store.saveVisit()

        #expect(try store.storedVisitJSON()["closedByObservedBoundaryReferenceBits"] == nil)
        let read = try #require(await store.visit())
        #expect(read.visitId == saved.visitId)
        #expect(read.closedByObservedBoundary == nil)
    }

    /// A state file written by the unshipped build that stored the closure as a date under
    /// `closedByObservedBoundary`: that key is ignored, not misread as a closure.
    @Test
    func closureUnderTheUnshippedDateKey_expectIgnored() async throws {
        let store = await Store(enteringBefore: Date(timeIntervalSinceReferenceDate: 810907800.1))
        _ = try await store.saveVisit()
        let before = try #require(await store.visit())
        try store.editStoredVisit { $0["closedByObservedBoundary"] = 1789215000.1 }

        #expect(await store.visit() == before)
    }

    /// Bits that are not a decimal pattern of a finite interval are rejected: the state does not
    /// decode, as for any malformed field, so no visit is read back as open. Not written by any
    /// build; the file is edited to simulate corruption.
    @Test(arguments: ["not-bits", String(Double.infinity.bitPattern), String(Double.nan.bitPattern), "-1"])
    func malformedClosureBits_expectRejected(bits: String) async throws {
        let store = await Store(enteringBefore: Date(timeIntervalSinceReferenceDate: 810907800.1))
        _ = try await store.saveVisit()
        try #require(await store.visit() != nil)
        try store.editStoredVisit { $0["closedByObservedBoundaryReferenceBits"] = bits }

        #expect(await store.visit() == nil)
    }

    // MARK: - Store

    private enum CodecTestError: Error { case notDelivered }

    /// A real state file with the circle cached, its monitor record seen inside, and a manual clock
    /// that started 600 s before the EXIT.
    private struct Store {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock: ManualGeofenceClock
        let dateUtil = DateUtilStub()
        let storage: GeofenceStorage

        init(enteringBefore exitedAt: Date) async {
            let entered = exitedAt.addingTimeInterval(-600)
            self.clock = ManualGeofenceClock(
                wall: entered, uptime: 10000,
                boot: GeofenceBootIdentity(bootTime: entered.timeIntervalSince1970 - 10000, processToken: nil)
            )
            dateUtil.givenNow = entered
            self.storage = GeofenceStorage(directoryURL: directory, dateUtil: dateUtil)
            await storage.setCachedGeofences([ClosedBoundaryCodecTests.circle])
            await storage.recordMonitorRegistration(
                identifier: ClosedBoundaryCodecTests.circle.id, transitionTypes: [.enter, .exit], initialState: .enter,
                center: LocationData(latitude: 1, longitude: 2), radius: 150, initialStateObserved: true, now: entered
            )
        }

        /// A visit entered now, as the coordinator records one.
        func saveVisit(reservation: GeofenceDwellReservation? = nil) async throws -> GeofenceDwellVisit {
            let visit = GeofenceDwellVisit(
                visitId: UUID().uuidString, enteredAt: clock.wall, geometryRevision: ClosedBoundaryCodecTests.circle.dwellRevision,
                userId: "user-a", emitted: false, entryObserved: true, dwellReservation: reservation,
                timing: GeofenceVisitTiming(enteredAt: clock.wall, recordedAt: clock.read())
            )
            try #require(await storage.saveDwellVisit(visit, geofenceId: ClosedBoundaryCodecTests.circle.id))
            return visit
        }

        /// The monitor's EXIT dated `exitedAt`, processed a moment after it, as `CLMonitor` records it.
        func recordExit(at exitedAt: Date) async throws {
            clock.advance(exitedAt.timeIntervalSince(clock.wall) + 0.05)
            dateUtil.givenNow = clock.wall
            let (outcome, _) = await storage.recordMonitorTransition(
                .exit, forIdentifier: ClosedBoundaryCodecTests.circle.id,
                onlyIfBaselinePredates: exitedAt, osEventDate: exitedAt, now: exitedAt, processedAt: clock.read()
            )
            guard case .deliver = outcome else { throw CodecTestError.notDelivered }
        }

        func visit() async -> GeofenceDwellVisit? {
            await storage.getDwellVisit(geofenceId: ClosedBoundaryCodecTests.circle.id)
        }

        private var stateFile: URL {
            directory.appendingPathComponent("geofenceState.json")
        }

        func storedVisitJSON() throws -> [String: Any] {
            let state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile)) as? [String: Any])
            let visits = try #require(state["dwellVisits"] as? [String: Any])
            return try #require(visits[ClosedBoundaryCodecTests.circle.id] as? [String: Any])
        }

        func editStoredVisit(_ edit: (inout [String: Any]) -> Void) throws {
            var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile)) as? [String: Any])
            var visits = try #require(state["dwellVisits"] as? [String: Any])
            var visit = try storedVisitJSON()
            edit(&visit)
            visits[ClosedBoundaryCodecTests.circle.id] = visit
            state["dwellVisits"] = visits
            try JSONSerialization.data(withJSONObject: state).write(to: stateFile, options: .atomic)
        }
    }
}
