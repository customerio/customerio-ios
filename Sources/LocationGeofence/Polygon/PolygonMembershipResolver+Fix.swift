import CioInternalCommon
import CoreLocation
import Foundation

/// How the resolver gets a position to judge against, split from its core for the file cap.
/// Members are `internal` only because of the split.
extension PolygonMembershipResolver {
    /// Whether a caller's fix can stand in for a request of our own. Recorded on the pass log so a
    /// drive can tell a reuse from a fall-through.
    enum HeldFixUse: String, CaseIterable {
        /// The caller held none; the pass requests its own.
        case none
        case reused
        case tooOld = "too_old"
        /// This resolver has since delivered a strictly NEWER fix, and the pass judged on that
        /// instead of the caller's.
        case newer
    }

    /// Reusing a caller's fix matters for more than the saved request: `resolveFix(requiringFresh:)`
    /// demands a fix strictly newer than the last one this resolver delivered, which is the
    /// caller's, so a second request answered by a CoreLocation echo is refused and every polygon
    /// in the pass records `no_usable_fix`.
    ///
    /// Past `movementFixMaxAge` the held fix would be refused as `fix_too_old` (a movement deferred
    /// at the gate replays with an older fix), so the pass requests instead.
    ///
    /// A newer fix this resolver already holds, such as a corroboration answer from the pass that
    /// handed this fix over, is used in its place. Reusing the older fix could re-propose an
    /// arrival that newer fix refused, and requesting would hit the same echo refusal.
    func heldFixUse(_ heldFix: ResolvedFix?) -> HeldFixDecision {
        guard let heldFix else { return HeldFixDecision(use: .none, age: 0, newerFix: nil) }
        if let latest = fixResolver.latestFix, latest.timestamp > heldFix.timestamp {
            // Judged on the NEWER fix's age, not the held one's: one fix, one age, and they differ.
            let age = dateUtil.now.timeIntervalSince(latest.timestamp)
            guard age <= GeofenceConstants.movementFixMaxAge else {
                // The newest thing held is itself past the cap, so the caller's is older still.
                return HeldFixDecision(use: .tooOld, age: age, newerFix: nil)
            }
            return HeldFixDecision(use: .newer, age: age, newerFix: latest)
        }
        let age = dateUtil.now.timeIntervalSince(heldFix.timestamp)
        return HeldFixDecision(
            use: age <= GeofenceConstants.movementFixMaxAge ? .reused : .tooOld, age: age, newerFix: nil
        )
    }

    /// The verdict on a caller's fix, with the age it was judged on so the pass never re-reads the
    /// clock. Re-reading can push a fix accepted just under `movementFixMaxAge` past it, so every
    /// polygon records `fix_too_old` while the `.tooOld` branch that would have requested a
    /// replacement never ran.
    struct HeldFixDecision {
        let use: HeldFixUse
        let age: TimeInterval
        /// Set only for `.newer`: the fix the pass judges on in place of the caller's.
        ///
        /// Kept as the real `CLLocation`: rebuilding it as a `ResolvedFix` would zero the altitude
        /// and drop vertical accuracy (see `ResolvedFix.location`).
        let newerFix: CLLocation?
    }

    /// A fix and the age settled for it when it was CHOSEN. One pass, one fix, one age.
    struct PassFix {
        let location: CLLocation
        let age: TimeInterval
    }

    /// The fix a pass judges against; see `heldFixUse` for when the caller's is taken.
    func passFix(heldFix: ResolvedFix?, decision: HeldFixDecision, requiringFresh: Bool) async -> PassFix? {
        // The age always comes from the decision, never a new reading.
        switch decision.use {
        case .reused:
            guard let heldFix else { return await requestedPassFix(requiringFresh: requiringFresh) }
            return PassFix(location: heldFix.location, age: decision.age)
        case .newer:
            guard let newerFix = decision.newerFix else {
                return await requestedPassFix(requiringFresh: requiringFresh)
            }
            return PassFix(location: newerFix, age: decision.age)
        case .none, .tooOld:
            return await requestedPassFix(requiringFresh: requiringFresh)
        }
    }

    /// Wraps a fix this resolver requested with the age it had on arrival.
    func requestedPassFix(requiringFresh: Bool) async -> PassFix? {
        guard let resolved = await resolveFix(requiringFresh: requiringFresh) else { return nil }
        return PassFix(location: resolved, age: dateUtil.now.timeIntervalSince(resolved.timestamp))
    }

    /// Freshest fix obtainable, requesting one when the cache is stale. The completion's
    /// coordinates are discarded for `latestFix`, which carries accuracy and timestamp.
    ///
    /// With `requiringFresh`, only a fix received for THIS request and strictly newer than the last
    /// one delivered counts. That is stricter than the coordinator's `wakeRadius` test, which only
    /// needs a fix within `movementFixMaxAge`; neither may be relaxed to the other.
    ///
    /// On a process's first pass nothing has been delivered yet, and CoreLocation may echo its
    /// cached fix as a new manager's first delivery, so a cold wake can be answered by a fix up to
    /// `movementFixMaxAge` old. The verdict log's fix age identifies such a verdict.
    func resolveFix(requiringFresh: Bool = false) async -> CLLocation? {
        // What this resolver has DELIVERED, which a forced request must improve on. Not
        // `cachedFix`: CoreLocation's cache advances on its own, so that baseline could be as new as
        // any answer and the guard below would never pass.
        let priorTimestamp = fixResolver.latestFix?.timestamp
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: requiringFresh ? nil : fixResolver.cachedFix, purpose: .polygon) { [weak self] _, isFresh in
                guard let self else { return continuation.resume(returning: nil) }
                let resolved = fixResolver.latestFix
                if requiringFresh {
                    // `isFresh` is true only for a fix received for this request, so a failed or
                    // timed-out request never resumes on the held fix. It does not prove the fix
                    // postdates the wake (an echoed cache fix within `movementFixMaxAge` passes),
                    // so the timestamp check keeps each later wake strictly ahead of the one before.
                    //
                    // No fallback to the held fix: a wake fires BECAUSE the device moved, so
                    // anything predating the request describes where it was.
                    guard isFresh, let resolved,
                          priorTimestamp.map({ resolved.timestamp > $0 }) ?? true
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: resolved)
                    return
                }
                // Newest fix from either source. Not `latestFix`: `resolve` answers from a young
                // cached fix WITHOUT recording it, so `latestFix` can be much older. Recording on
                // that path instead would let the system cache advance the forced-fresh baseline
                // above until nothing could beat it. Also covers a cold process whose request
                // failed, where CoreLocation's cache is the only evidence.
                continuation.resume(returning: fixResolver.cachedFix)
            }
        }
    }
}
