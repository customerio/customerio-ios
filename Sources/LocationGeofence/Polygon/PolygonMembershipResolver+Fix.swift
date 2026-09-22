import CioInternalCommon
import CoreLocation
import Foundation

/// How the resolver gets a position to judge against, split from its core so both stay under the
/// file cap. `internal` rather than `private` only because of that split; it remains
/// implementation detail of the resolver.
extension PolygonMembershipResolver {
    /// Whether a caller's fix can stand in for a request of our own. Recorded on the pass log so a
    /// drive can tell a reuse from a fall-through.
    enum HeldFixUse: String, CaseIterable {
        /// The caller held none; the pass requests its own, as it always has.
        case none
        case reused
        case tooOld = "too_old"
        /// This resolver has since delivered a strictly NEWER fix, and the pass judged on that
        /// instead of the caller's.
        case newer
    }

    /// A caller that already resolved a fix under the same freshness rule must not be made to ask
    /// again, and not only to save the request. `resolveFix(requiringFresh:)` demands a fix
    /// strictly newer than the last one this resolver delivered — which is the caller's — so the
    /// second request is refused whenever CoreLocation echoes that fix, as it commonly does within
    /// seconds of delivering it. Every polygon in the pass then records `no_usable_fix`: the whole
    /// pass lost, not one request wasted.
    ///
    /// Age is the limit. A movement deferred at the gate replays with the fix it was recorded
    /// with, older by however long the holder ran — a remote refetch is seconds, and unbounded on
    /// a slow network. `PolygonMembershipDecision` refuses anything past `movementFixMaxAge` as
    /// `fix_too_old`, so reusing one there loses the same pass by the other route. Past the cap we
    /// request instead, which also beats the stale baseline the guard above compares against.
    /// A newer fix this resolver already holds WINS over the caller's, and is used in its place
    /// rather than triggering a request.
    ///
    /// The pass that handed this fix over can itself have spent a corroboration request and been
    /// answered with a newer fix. If that answer contradicted — a marginal inside, refused because
    /// the second fix read outside — then reusing the held fix re-proposes exactly the arrival the
    /// entry pass correctly refused, and the corroboration it asks for is refused as an echo of
    /// the newer fix, so it commits UNCONFIRMED on older evidence.
    ///
    /// Substituting rather than requesting, because REFUSING reuse is the over-correction: when
    /// the corroboration AGREED, forcing a request hits the same echo refusal this whole path
    /// exists to avoid, and loses every polygon in the pass to `no_usable_fix`. The newer fix is
    /// both the better evidence and free, so take it and spend no request either way.
    func heldFixUse(_ heldFix: ResolvedFix?) -> HeldFixDecision {
        guard let heldFix else { return HeldFixDecision(use: .none, age: 0, newerFix: nil) }
        if let latest = fixResolver.latestFix, latest.timestamp > heldFix.timestamp {
            // Judged on the NEWER fix's age, not the held one's: one fix, one age, and they differ.
            let age = -latest.timestamp.timeIntervalSinceNow
            guard age <= GeofenceConstants.movementFixMaxAge else {
                // The newest thing held is itself past the cap, so the caller's is older still.
                return HeldFixDecision(use: .tooOld, age: age, newerFix: nil)
            }
            return HeldFixDecision(use: .newer, age: age, newerFix: latest)
        }
        let age = -heldFix.timestamp.timeIntervalSinceNow
        return HeldFixDecision(
            use: age <= GeofenceConstants.movementFixMaxAge ? .reused : .tooOld, age: age, newerFix: nil
        )
    }

    /// The verdict on a caller's fix, carrying the age it was judged on so the pass does not ask
    /// again. The two reads are not interchangeable: accepting at 29.9 s and re-reading the clock
    /// at the start of the pass puts the fix past `movementFixMaxAge`, and every polygon then
    /// records `fix_too_old` — while `.tooOld`, the branch that would have requested a usable
    /// replacement, was never taken. Measured in the field at a 29.95 s held fix.
    struct HeldFixDecision {
        let use: HeldFixUse
        let age: TimeInterval
        /// Set only for `.newer`: the fix the pass judges on in place of the caller's.
        ///
        /// A real `CLLocation`, and it must stay one. Rebuilding it as a `ResolvedFix` for
        /// symmetry with the held path would zero the altitude and drop the vertical accuracy —
        /// which is exactly the coarse-cell-fix signature our drive analysis reads, and which
        /// `ResolvedFix` warns about on its own `location`.
        let newerFix: CLLocation?
    }

    /// A fix and the age settled for it when it was CHOSEN. One pass, one fix, one age.
    struct PassFix {
        let location: CLLocation
        let age: TimeInterval
    }

    /// The fix a pass judges against — see `heldFixUse` for when the caller's is taken.
    func passFix(heldFix: ResolvedFix?, decision: HeldFixDecision, requiringFresh: Bool) async -> PassFix? {
        // The age always comes from the decision, never a new reading: that is the whole point of
        // carrying it.
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
        return PassFix(location: resolved, age: -resolved.timestamp.timeIntervalSinceNow)
    }

    func resolveFix(requiringFresh: Bool = false) async -> CLLocation? {
        // What this resolver has already DELIVERED, which is what a forced request must improve on.
        // Deliberately not `cachedFix`: that reports the newest fix obtainable from either source,
        // and CoreLocation's own cache advances on its own, so using it here makes the baseline as
        // current as any answer a request can return and the guard below can never pass.
        let priorTimestamp = fixResolver.latestFix?.timestamp
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: requiringFresh ? nil : fixResolver.cachedFix, purpose: .polygon) { [weak self] _, isFresh in
                guard let self else { return continuation.resume(returning: nil) }
                let resolved = fixResolver.latestFix
                if requiringFresh {
                    // `isFresh` is the resolver's own account of what it answered with: true only
                    // for a fix it received in response to this request, which is what keeps a
                    // failed or timed-out request from resuming on the held fix. It does NOT prove
                    // the fix postdates the wake — an echoed cache fix inside `movementFixMaxAge`
                    // clears it — so on a cold process the age gate is the whole bound. The
                    // timestamp comparison then keeps each later wake strictly ahead of the one before.
                    //
                    // No fallback to the held fix here, on any branch: a wake fires BECAUSE the
                    // device moved, so anything predating the request describes where it was.
                    guard isFresh, let resolved,
                          priorTimestamp.map({ resolved.timestamp > $0 }) ?? true
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: resolved)
                    return
                }
                // Newest of whatever exists, which is what a pass content with a held fix wants.
                // Not `latestFix` first: `resolve` answers from the caller's cached fix WITHOUT
                // recording it when that fix is young enough, so `latestFix` can be much older than
                // the system fix that let this pass proceed. Fixed here and not by recording on
                // that fast path — letting `latestFix` absorb the system cache would make the
                // forced-fresh baseline above unbeatable again, the defect this path was repaired
                // from. It also covers a cold process whose request failed, where CoreLocation's
                // cache is the only evidence and the monitor's dedup baseline has already advanced.
                continuation.resume(returning: fixResolver.cachedFix)
            }
        }
    }
}
