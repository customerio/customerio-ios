import CioInternalCommon
import CoreLocation
import Foundation

extension PolygonMembershipResolver {
    /// Two phases: settle everything the fix alone decides, then corroborate marginal arrivals.
    /// Corroborating inline would age the fix for every later polygon.
    func runPass(
        geofenceIds: [String],
        fix: PassFix,
        pass: Int,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        // Polygons are judged here; a circle's visit only learns of a fix that proves the device
        // away from it. Before the polygons, so the fix is no older than the pass chose it at. Not
        // gated on `isStillCurrent`: like a belief, a position is true whoever is signed in, and
        // only the identified user's own visit is read.
        await dwellCoordinator?.recordOutsideEvidence(fix: fix.location, expectedUserId: nil)
        // Per pass, not per resolver; see `PassCorroboration`.
        let cache = PassCorroboration()
        var deferred: [DeferredCorroboration] = []
        for geofenceId in geofenceIds {
            if let pending = await evaluate(
                geofenceId: geofenceId, fix: fix, pass: pass, isStillCurrent: isStillCurrent
            ) {
                deferred.append(pending)
            }
        }
        for pending in deferred {
            // Re-read per polygon, right before the request: phase one and earlier corroborations
            // can land an inside belief after classification.
            guard await storage.getPolygonMembership()[pending.geofence.id]?.membership != .inside
            else {
                logger.geofencePolygonUndecided(
                    identifier: pending.geofence.id,
                    reason: PolygonUndecidedReason.corroborationUnnecessary,
                    signedEdgeDistance: pending.signedEdgeDistance,
                    horizontalAccuracy: fix.location.horizontalAccuracy,
                    pass: pass
                )
                continue
            }
            let corroboration: VerdictCorroboration
            switch await corroborate(pending, firstFix: fix.location, cache: cache, pass: pass) {
            case .confirmed: corroboration = .confirmed
            case .unconfirmed(let reason): corroboration = .unconfirmed(reason)
            case .contradicted: continue
            }
            await record(
                PolygonVerdict(
                    membership: pending.proposed, corroboration: corroboration,
                    signedEdgeDistance: pending.signedEdgeDistance, pass: pass
                ),
                for: pending.geofence, fix: fix.location, isStillCurrent: isStillCurrent
            )
        }
    }

    /// The logged age is at RECORD time, so a corroborated verdict can log one past
    /// `movementFixMaxAge`.
    func record(
        _ verdict: PolygonVerdict,
        for geofence: Geofence,
        fix: CLLocation,
        isStillCurrent: (@Sendable () -> Bool)?
    ) async {
        logger.geofencePolygonVerdict(
            identifier: geofence.id, verdict: verdict,
            horizontalAccuracy: fix.horizontalAccuracy,
            fixAge: dateUtil.now.timeIntervalSince(fix.timestamp)
        )
        await apply(
            verdict.membership, to: geofence, evidence: fix.timestamp,
            confirmedByFix: true, evaluatedRing: geofence.vertices, isStillCurrent: isStillCurrent
        )
    }
}

struct PolygonVerdict {
    let membership: PolygonMembership
    let corroboration: VerdictCorroboration
    let signedEdgeDistance: Double
    let pass: Int
}

/// Three states, not a Bool, so an unconfirmed arrival isn't logged as not needing a second fix.
enum VerdictCorroboration: Equatable {
    case notNeeded
    case confirmed
    case unconfirmed(PolygonUndecidedReason)

    /// The cross-SDK `cor` key: whether a second fix agreed (false for `.notNeeded`).
    var confirmed: Bool { self == .confirmed }

    /// `nil` unless unconfirmed, so the key is absent on decisive verdicts.
    var unconfirmedReason: String? {
        guard case .unconfirmed(let reason) = self else { return nil }
        return reason.rawValue
    }
}
