import CioInternalCommon
import CoreLocation
import Foundation

/// How the resolver gets a position to judge against, split from its core so both stay under the
/// file cap. `internal` rather than `private` only because of that split; it remains
/// implementation detail of the resolver.
extension PolygonMembershipResolver {
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
