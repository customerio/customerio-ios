import CioInternalCommon
import CoreLocation
import Foundation

extension PolygonMembershipResolver {
    enum HeldFixUse: String, CaseIterable {
        case none
        case reused
        case tooOld = "too_old"
        /// The pass judged on a newer fix this resolver had since delivered.
        case newer
    }

    /// Reuse isn't just a saving: `resolveFix(requiringFresh:)` must beat the caller's fix, so a
    /// second request answered by a CoreLocation echo is refused.
    func heldFixUse(_ heldFix: ResolvedFix?) -> HeldFixDecision {
        guard let heldFix else { return HeldFixDecision(use: .none, age: 0, newerFix: nil) }
        if let latest = fixResolver.latestFix, latest.timestamp > heldFix.timestamp {
            // Judged on the NEWER fix's age, not the held one's.
            let age = dateUtil.now.timeIntervalSince(latest.timestamp)
            guard age <= GeofenceConstants.movementFixMaxAge else {
                return HeldFixDecision(use: .tooOld, age: age, newerFix: nil)
            }
            return HeldFixDecision(use: .newer, age: age, newerFix: latest)
        }
        let age = dateUtil.now.timeIntervalSince(heldFix.timestamp)
        return HeldFixDecision(
            use: age <= GeofenceConstants.movementFixMaxAge ? .reused : .tooOld, age: age, newerFix: nil
        )
    }

    /// Carries the age it was judged on so the pass never re-reads the clock.
    struct HeldFixDecision {
        let use: HeldFixUse
        let age: TimeInterval
        /// Only for `.newer`. Kept as `CLLocation`: a `ResolvedFix` would drop altitude.
        let newerFix: CLLocation?
    }

    /// `age` is settled when the fix is CHOSEN, not re-read later.
    struct PassFix {
        let location: CLLocation
        let age: TimeInterval
    }

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

    func requestedPassFix(requiringFresh: Bool) async -> PassFix? {
        guard let resolved = await resolveFix(requiringFresh: requiringFresh) else { return nil }
        return PassFix(location: resolved, age: dateUtil.now.timeIntervalSince(resolved.timestamp))
    }

    /// With `requiringFresh`, only a fix received for THIS request and newer than the last delivered
    /// counts. Stricter than the coordinator's `wakeRadius` test; neither may be relaxed to the other.
    func resolveFix(requiringFresh: Bool = false) async -> CLLocation? {
        // Not `cachedFix`: CoreLocation's cache advances on its own, so the guard below would never
        // pass.
        let priorTimestamp = fixResolver.latestFix?.timestamp
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: requiringFresh ? nil : fixResolver.cachedFix, purpose: .polygon) { [weak self] _, isFresh in
                guard let self else { return continuation.resume(returning: nil) }
                let resolved = fixResolver.latestFix
                if requiringFresh {
                    // `isFresh` alone lets an echoed cache fix through; the timestamp check stops it.
                    // No fallback to the held fix: a wake means the device moved.
                    guard isFresh, let resolved,
                          priorTimestamp.map({ resolved.timestamp > $0 }) ?? true
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: resolved)
                    return
                }
                // Not `latestFix`, which a cached answer doesn't update. Recording the cached answer
                // instead would let the system cache push the forced-fresh baseline past anything.
                continuation.resume(returning: fixResolver.cachedFix)
            }
        }
    }
}
