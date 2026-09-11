import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Movement trigger

//
// Split out of `Logger+Geofence.swift` for the file-length cap. The movement trigger is its own
// mechanism — re-centring, the refetch tier, and the fix a pass runs on — and these records are
// read together when calibrating the wake margin.

extension Logger {
    func geofenceMovementTrigger(tier: HandleMovementTier) {
        debug(
            "Movement trigger EXIT: \(tier.rawValue)"
                + geofenceTail("movement.exit", .input, [("tier", tier.rawValue)]),
            geofenceTag
        )
    }

    /// The re-centred bubble's own geometry. Region geometry is ungated — it is workspace
    /// configuration, not user data — but this one is derived from the device's position, so it
    /// travels with the same switch as a coordinate.
    func geofenceMovementTriggerRegistered(latitude: Double, longitude: Double, radius: Double) {
        let geometry: [(String, String?)] = [
            ("rlat", GeofenceLog.num(latitude, 5)),
            ("rlon", GeofenceLog.num(longitude, 5))
        ]
        debug(
            "Movement trigger registered with radius \(Int(radius)) m"
                + geofenceTail("movement.registered", .output, geometry + [("rad", GeofenceLog.num(radius, 0))]),
            geofenceTag
        )
    }

    func geofenceMovementRearmedAfterFailedRefresh() {
        debug(
            "Movement refresh failed; re-ranking from cache to re-arm the movement trigger"
                + geofenceTail("movement.rearmed", .output, [("why", "refresh_failed")]),
            geofenceTag
        )
    }

    /// `spd` rides here and not only on `os.callback.received`: the wake margin is sized from how
    /// far the device travels between passes, and this is the fix a pass actually uses. Speed at
    /// OS-callback time is a different population — it only samples moments the OS chose to wake us.
    func geofenceMovementFixResolved(ageSeconds: TimeInterval, requested: Bool, speed: CLLocationSpeed? = nil, purpose: GeofenceFixPurpose? = nil) {
        let source = requested ? "freshly requested" : "cached"
        debug(
            "Movement pass using \(source) fix, age \(String(format: "%.1f", ageSeconds))s"
                + geofenceTail("movement.fix.resolved", .input, [
                    ("age", GeofenceLog.num(ageSeconds)),
                    ("prov", requested ? "requested" : "cached"),
                    // Negative means the fix carries no speed, which is not the same as stationary.
                    ("spd", speed.flatMap { $0 >= 0 ? GeofenceLog.num($0) : nil }),
                    // Which decision asked. `prov` separates cached from requested; this separates
                    // the five callers, whose speed samples are different populations.
                    ("for", purpose?.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixStale(ageSeconds: TimeInterval?) {
        let age = ageSeconds.map { "\(String(format: "%.1f", $0))s old" } ?? "missing"
        info(
            "Cached fix is \(age); requesting a fresh fix for the movement pass"
                + geofenceTail("movement.fix.requested", .output, [
                    ("age", GeofenceLog.num(ageSeconds)),
                    ("why", ageSeconds == nil ? "no_cached_fix" : "stale_cached_fix")
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixRequestFailed(fallingBackToCached: Bool, elapsed: TimeInterval? = nil) {
        let outcome = fallingBackToCached ? "falling back to the stale cached fix" : "no cached fix to fall back to"
        info(
            "Fresh-fix request failed or timed out; \(outcome)"
                + geofenceTail("movement.fix.failed", .input, [
                    ("ok", GeofenceLog.bool(false)),
                    ("why", fallingBackToCached ? "fallback_cached" : "no_fallback"),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }
}
