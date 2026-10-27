@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A refresh can replace a circle under the same id while the monitor still holds, and reports
/// events from, the old one. A circle event's visit must come from the circle the dwell is measured
/// against: the event's attributed circle must match the cached one as registered (clamped to the
/// cap), a cold-wake event with no recorded generation counts as current, and one whose circle is
/// known gone does not. Delivery itself is unchanged. Driven through the resolver's
/// `handleTransition`, which the binder's routing task calls, into the real coordinator, storage,
/// tracker and file outbox (`GeofenceDwellFollowupTests.Rig`); only the clock, the fix and HTTP are
/// scripted.
@Suite("CircleEventProvenance", .serialized)
@MainActor
struct CircleEventProvenanceTests {
    private static let center = LocationData(latitude: 1, longitude: 2)
    /// The current circle: the old 150 m one at the same centre, edited to 200 m.
    private static let current = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 200, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 2),
        dwellThresholdSeconds: 600
    )
    private static let oldCircle = GeofenceEventCircle.circle(MonitoredCircle(center: center, radius: 150, maximumRadius: 100000))
    private static let currentCircle = GeofenceEventCircle.circle(MonitoredCircle(center: center, radius: 200, maximumRadius: 100000))

    /// The old circle's ENTER arrives after the edit. It is delivered, but starts no visit and so
    /// no dwell. The current circle's ENTER then starts the stay, which qualifies with its entry.
    @Test
    func oldCircleEnterAfterAnEdit_expectDeliveredWithoutAVisit() async throws {
        let (rig, resolver) = await Self.rig(current: Self.current)
        await Self.enter(resolver, rig: rig, raisedBy: Self.oldCircle)

        #expect(await rig.outbox.rows().filter { $0.transition == .enter }.count == 1)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.current.id) == nil)
        rig.advance(30)
        let enteredAt = rig.clock.wall
        await Self.enter(resolver, rig: rig, raisedBy: Self.currentCircle)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: Self.current.id))
        rig.dwell.cancelEvidence(for: Self.current.id)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.current.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].enteredAt == enteredAt)
        rig.dwell.cancelEvidence(for: Self.current.id)
        withExtendedLifetime(resolver) {}
    }

    /// A cold-wake ENTER (no recorded generation) counts as the current circle's and starts a
    /// visit; one whose circle is known gone starts none. Both are delivered.
    @Test(arguments: [true, false])
    func enterOfAnUnattributedCircle_expectAVisitOnlyForColdWake(coldWake: Bool) async throws {
        let (rig, resolver) = await Self.rig(current: Self.current)
        await Self.enter(resolver, rig: rig, raisedBy: coldWake ? .unknown : .expired)

        #expect(await rig.outbox.rows().filter { $0.transition == .enter }.count == 1)
        #expect((await rig.storage.getDwellVisit(geofenceId: Self.current.id) != nil) == coldWake)
        rig.dwell.cancelEvidence(for: Self.current.id)
        withExtendedLifetime(resolver) {}
    }

    /// Control: a 150 m circle under a 100 m cap is registered, and reports events, at 100 m. That
    /// is the current circle, clamped, and its ENTER starts a visit.
    @Test
    func clampedCurrentCircleEnter_expectAVisit() async throws {
        let fence = Geofence(
            id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 2),
            dwellThresholdSeconds: 600
        )
        let (rig, resolver) = await Self.rig(current: fence)
        await Self.enter(resolver, rig: rig, raisedBy: .circle(MonitoredCircle(center: Self.center, radius: 100, maximumRadius: 100)))

        #expect(await rig.storage.getDwellVisit(geofenceId: fence.id) != nil)
        rig.dwell.cancelEvidence(for: fence.id)
        withExtendedLifetime(resolver) {}
    }

    /// The old circle's ENTER, dated after a current stay whose dwell went out (or was reserved),
    /// leaves that stay exactly as it was: no visit is started, and nothing is reset.
    @Test(arguments: [false, true])
    func oldCircleEnterOverAQualifiedStay_expectItUnchanged(reserved: Bool) async throws {
        let (rig, resolver) = await Self.rig(current: Self.current)
        await Self.enter(resolver, rig: rig, raisedBy: Self.currentCircle)
        let stay = try #require(await rig.storage.getDwellVisit(geofenceId: Self.current.id))
        rig.dwell.cancelEvidence(for: Self.current.id)
        rig.advance(600)
        if reserved {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64((rig.clock.wall.timeIntervalSince1970 * 1000).rounded()),
                enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600, detectionSource: "location_evidence"
            )
            guard case .reserved = await rig.storage.reserveDwellEmission(reservation, for: stay, geofenceId: Self.current.id) else {
                Issue.record("not reserved")
                return
            }
        } else {
            await rig.dwell.requestQualifyingEvidence(geofenceId: Self.current.id)
        }
        rig.dwell.cancelEvidence(for: Self.current.id)
        let qualified = try #require(await rig.storage.getDwellVisit(geofenceId: Self.current.id))
        rig.advance(60)
        await Self.enter(resolver, rig: rig, raisedBy: Self.oldCircle)

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.current.id) == qualified)
        rig.dwell.cancelEvidence(for: Self.current.id)
        withExtendedLifetime(resolver) {}
    }

    /// The old circle's EXIT, or one whose circle is known gone, says nothing about the current
    /// circle: the stay whose dwell went out is kept as it was, with no EXIT recorded against it,
    /// and the public EXIT is still delivered. A fresh inside fix 600 s later queues no second DWELL.
    @Test(arguments: [false, true])
    func unprovenExitOverAnEmittedStay_expectKeptAndDelivered(expired: Bool) async throws {
        let (rig, resolver) = await Self.rig(current: Self.current)
        await Self.enter(resolver, rig: rig, raisedBy: Self.currentCircle)
        rig.dwell.cancelEvidence(for: Self.current.id)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.current.id)
        let emitted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.current.id))
        try #require(emitted.emitted)
        rig.advance(60)
        await resolver.handleTransition(
            identifier: Self.current.id, transition: .exit, occurredAt: rig.clock.wall,
            eventCircle: expired ? .expired : Self.oldCircle, receivedForUserId: "user-1"
        )

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.current.id) == emitted)
        #expect(rig.dwell.exitMarks[Self.current.id] == nil)
        #expect(await rig.outbox.rows().filter { $0.transition == .exit }.count == 1)
        rig.advance(600)
        await rig.dwell.recordInsideEvidence(geofence: Self.current, at: rig.clock.wall, source: "location_evidence")
        #expect(await rig.dwellRows().map(\.visitId) == [emitted.visitId])
        rig.dwell.cancelEvidence(for: Self.current.id)
        withExtendedLifetime(resolver) {}
    }

    // MARK: - Helpers

    /// The rig, with `current` cached in place of the 150 m circle it was registered as; a CDP key,
    /// so a flush keeps rows in the outbox. Fresh fixes are at the shared centre, inside both.
    private static func rig(current: Geofence) async -> (GeofenceDwellFollowupTests.Rig, PolygonMembershipResolver) {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        rig.contextStore.setCdpApiKey("test-key")
        await rig.cacheCircle()
        await rig.storage.setCachedGeofences([current])
        let resolver = PolygonMembershipResolver(
            storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
            dateUtil: rig.dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: rig.dwell
        )
        return (rig, resolver)
    }

    /// An ENTER the monitor attributed to `raisedBy`, routed now.
    private static func enter(
        _ resolver: PolygonMembershipResolver, rig: GeofenceDwellFollowupTests.Rig, raisedBy: GeofenceEventCircle
    ) async {
        await resolver.handleTransition(
            identifier: current.id, transition: .enter, occurredAt: rig.clock.wall, eventCircle: raisedBy,
            receivedForUserId: "user-1"
        )
    }
}
