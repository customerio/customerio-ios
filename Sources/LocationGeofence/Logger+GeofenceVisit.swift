import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    // MARK: - Visits

    /// Recorded at start and stop, not only per report, so "no visit landed" and "visits were
    /// never armed" look different in a capture.
    func geofenceVisitMonitoringStarted() {
        info(
            "Visit monitoring armed"
                + geofenceTail("visit.monitoring", .observation, [("state", "started")]),
            geofenceTag
        )
    }

    func geofenceVisitMonitoringStopped() {
        info(
            "Visit monitoring disarmed"
                + geofenceTail("visit.monitoring", .observation, [("state", "stopped")]),
            geofenceTag
        )
    }

    /// `status` is the raw `CLAuthorizationStatus`.
    func geofenceVisitMonitoringSkipped(status: Int32) {
        info(
            "Visit monitoring needs Always authorization"
                + geofenceTail("visit.monitoring", .observation, [
                    ("state", "skipped"),
                    ("why", "not_always"),
                    ("status", String(status))
                ]),
            geofenceTag
        )
    }

    /// `delay` is how long after the visit edge iOS reported it: routinely minutes, which is why
    /// the visit coordinate is never used as an anchor.
    func geofenceVisitReported(
        coordinate: LocationData,
        isArrival: Bool,
        horizontalAccuracy: Double,
        reportDelay: TimeInterval
    ) {
        debug(
            "Visit \(isArrival ? "arrival" : "departure") reported after \(Int(reportDelay))s"
                + geofenceTail("visit.reported", .input, [
                    ("edge", isArrival ? "arrival" : "departure"),
                    // An OS-delivered input, so the transcript carries it. Never an anchor.
                    ("lat", GeofenceLog.num(coordinate.latitude, 5)),
                    ("lon", GeofenceLog.num(coordinate.longitude, 5)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("delay", GeofenceLog.num(reportDelay, 0))
                ]),
            geofenceTag
        )
    }
}
