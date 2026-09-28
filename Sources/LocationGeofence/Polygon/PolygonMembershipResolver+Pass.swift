import CioInternalCommon
import CoreLocation
import Foundation

/// How a pass is sequenced over the polygons it judges, split from the resolver's core for the
/// file cap. Members are `internal` only because of the split.
extension PolygonMembershipResolver {
    /// Runs one pass over `geofenceIds` against a single fix in TWO phases: everything the fix
    /// alone can decide is settled first, and only then are the marginal arrivals corroborated.
    ///
    /// Corroborating inline would let one marginal polygon's request (up to
    /// `movementFixRequestTimeout`) age the fix past `movementFixMaxAge` for every polygon after
    /// it, so one venue's arrival would depend on another venue and on catalog order.
    func runPass(
        geofenceIds: [String],
        fix: PassFix,
        pass: Int,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
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
            // An ambiguous INSIDE cannot move a belief that already says inside, so a second fix
            // would only reach `no_change`. Re-read per polygon, right before the request: phase
            // one and earlier corroborations can both land that belief after classification.
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
            // Only a second fix that positively reads OUTSIDE blocks the arrival. Everything
            // else commits, carrying on the verdict why it could not be confirmed.
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

    /// Logs the verdict and applies it, so both phases record identically apart from `cor`.
    ///
    /// The logged age is the fix's age AT RECORD TIME. On a corroborated verdict the second
    /// request sits in between, so the age can exceed `movementFixMaxAge` although the gate passed.
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

/// A settled verdict and how it was reached, carried together so both pass phases record one.
struct PolygonVerdict {
    let membership: PolygonMembership
    let corroboration: VerdictCorroboration
    let signedEdgeDistance: Double
    /// Which pass produced it; see `geofencePolygonVerdict`'s `pass` key.
    let pass: Int
}

/// How a recorded verdict stands with respect to a second fix. Three states, not a Bool, so an
/// uncorroborated marginal arrival is not logged as though no second fix was wanted.
enum VerdictCorroboration: Equatable {
    /// Decisive on one fix; no second was asked for.
    case notNeeded
    /// A second, independent fix agreed.
    case confirmed
    /// Marginal, and committed anyway because no second opinion could be had.
    case unconfirmed(PolygonUndecidedReason)

    /// The shared cross-SDK `cor` boolean: whether a second fix agreed.
    var confirmed: Bool { self == .confirmed }

    /// `nil` unless the arrival committed without confirmation, so the key is absent on every
    /// decisive verdict rather than carrying a placeholder.
    var unconfirmedReason: String? {
        guard case .unconfirmed(let reason) = self else { return nil }
        return reason.rawValue
    }
}
