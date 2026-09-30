import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Movement trigger

extension Logger {
    func geofenceMovementTrigger(tier: HandleMovementTier) {
        debug(
            "Movement trigger EXIT: \(tier.rawValue)"
                + geofenceTail("movement.exit", .observation, [("tier", tier.rawValue)]),
            geofenceTag
        )
    }

    /// The centre is the device's position.
    func geofenceMovementTriggerRegistered(latitude: Double, longitude: Double, radius: Double) {
        let geometry: [(String, String?)] = [
            ("rlat", GeofenceLog.num(latitude, 5)),
            ("rlon", GeofenceLog.num(longitude, 5))
        ]
        debug(
            "Movement trigger registered with radius \(Int(radius)) m"
                + geofenceTail("movement.registered", .observation, geometry + [("rad", GeofenceLog.num(radius, 0))]),
            geofenceTag
        )
    }

    func geofenceMovementRearmedAfterFailedRefresh() {
        debug(
            "Movement refresh failed; re-ranking from cache to re-arm the movement trigger"
                + geofenceTail("movement.rearmed", .observation, [("why", "refresh_failed")]),
            geofenceTag
        )
    }

    func geofenceMovementFixResolved(ageSeconds: TimeInterval, requested: Bool, speed: CLLocationSpeed? = nil, purpose: GeofenceFixPurpose? = nil) {
        let source = requested ? "freshly requested" : "cached"
        debug(
            "Movement pass using \(source) fix, age \(String(format: "%.1f", ageSeconds))s"
                + geofenceTail("movement.fix.resolved", .observation, [
                    ("age", GeofenceLog.num(ageSeconds, 6)),
                    ("prov", requested ? "requested" : "cached"),
                    // Negative means the fix carries no speed, which is not the same as stationary.
                    ("spd", speed.flatMap { $0 >= 0 ? GeofenceLog.num($0) : nil }),
                    ("for", purpose?.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixStale(ageSeconds: TimeInterval?) {
        let age = ageSeconds.map { "\(String(format: "%.1f", $0))s old" } ?? "missing"
        info(
            "Cached fix is \(age); requesting a fresh fix for the movement pass"
                + geofenceTail("movement.fix.requested", .observation, [
                    ("age", GeofenceLog.num(ageSeconds, 6)),
                    ("why", ageSeconds == nil ? "no_cached_fix" : "stale_cached_fix")
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixRequestFailed(fallingBackToCached: Bool, elapsed: TimeInterval? = nil) {
        let outcome = fallingBackToCached ? "falling back to the stale cached fix" : "no cached fix to fall back to"
        info(
            "Fresh-fix request failed or timed out; \(outcome)"
                + geofenceTail("movement.fix.failed", .observation, [
                    ("ok", GeofenceLog.bool(false)),
                    ("why", fallingBackToCached ? "fallback_cached" : "no_fallback"),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }
}
