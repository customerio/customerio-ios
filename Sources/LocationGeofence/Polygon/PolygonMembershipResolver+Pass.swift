import CioInternalCommon
import CoreLocation
import Foundation

/// How a pass is sequenced over the polygons it judges, split from the resolver's core so both
/// stay under the file cap. These are `internal` rather than `private` only because of that
/// split; they remain implementation detail of the resolver.
extension PolygonMembershipResolver {
    /// Runs one pass over `geofenceIds` against a single fix in TWO phases: everything the fix
    /// alone can decide is settled first, and only then are the marginal arrivals corroborated.
    ///
    /// The order is the point. Corroborating inline let one marginal polygon's request burn its
    /// `movementFixRequestTimeout` in the middle of the loop, handing every polygon after it the
    /// same fix ten seconds older — enough to push a fix that was decisive when the pass started
    /// past `movementFixMaxAge` and have it refused as `fix_too_old`. An arrival at one venue then
    /// depended on whether an unrelated venue happened to be marginal, and on catalog order.
    func runPass(
        geofenceIds: [String],
        fix: CLLocation,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        // Created here, so the pass owns it: see `PassCorroboration` for why resolver-level state
        // let overlapping fresh passes answer each other's corroboration requests.
        let cache = PassCorroboration()
        var deferred: [DeferredCorroboration] = []
        for geofenceId in geofenceIds {
            if let pending = await evaluate(
                geofenceId: geofenceId, fix: fix, isStillCurrent: isStillCurrent
            ) {
                deferred.append(pending)
            }
        }
        for pending in deferred {
            // Re-read per polygon, immediately before the request, and not once for the batch:
            // an ambiguous INSIDE cannot move a belief that already says inside, so a second fix
            // would buy a forced request (up to `movementFixRequestTimeout`) only to reach
            // `no_change`. Phase one, and phase two's own awaits, can both land that belief after
            // this polygon was classified — so a value read any earlier is the wrong value.
            guard await storage.getPolygonMembership()[pending.geofence.id]?.membership != .inside
            else {
                logger.geofencePolygonUndecided(
                    identifier: pending.geofence.id,
                    reason: PolygonUndecidedReason.corroborationUnnecessary,
                    signedEdgeDistance: pending.signedEdgeDistance,
                    horizontalAccuracy: fix.horizontalAccuracy
                )
                continue
            }
            guard await corroborate(pending, firstFix: fix, cache: cache) else { continue }
            await record(
                PolygonVerdict(
                    membership: pending.proposed, corroborated: true,
                    signedEdgeDistance: pending.signedEdgeDistance
                ),
                for: pending.geofence, fix: fix, isStillCurrent: isStillCurrent
            )
        }
    }

    /// Logs the verdict and applies it. Shared by both phases so a corroborated arrival and a
    /// decisive one are recorded identically apart from `cor`.
    ///
    /// `age` is the pass fix's age AT RECORD TIME, not at the moment it was judged. On a
    /// `cor=true` verdict those differ: the corroboration request sits between them and can run
    /// to `movementFixRequestTimeout`, so the logged age can exceed `movementFixMaxAge` on a
    /// verdict whose gate passed cleanly. Reading it as a leaked gate is the obvious mistake.
    func record(
        _ verdict: PolygonVerdict,
        for geofence: Geofence,
        fix: CLLocation,
        isStillCurrent: (@Sendable () -> Bool)?
    ) async {
        logger.geofencePolygonVerdict(
            identifier: geofence.id, membership: verdict.membership,
            signedEdgeDistance: verdict.signedEdgeDistance,
            horizontalAccuracy: fix.horizontalAccuracy,
            fixAge: -fix.timestamp.timeIntervalSinceNow,
            corroborated: verdict.corroborated
        )
        await apply(
            verdict.membership, to: geofence, evidence: fix.timestamp,
            confirmedByFix: true, evaluatedRing: geofence.vertices, isStillCurrent: isStillCurrent
        )
    }
}

/// A settled verdict and how it was reached, carried together so both pass phases record one.
struct PolygonVerdict {
    let membership: PolygonMembership
    let corroborated: Bool
    let signedEdgeDistance: Double
}
