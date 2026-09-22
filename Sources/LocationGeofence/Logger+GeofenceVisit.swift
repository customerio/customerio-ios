import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

/// The visit wake's own records. Split from `+Lifecycle` so both stay under the file cap.
extension Logger {
    // MARK: - Visits

    /// The wake source that does not need an edge crossing. Recorded at start/stop as well as on
    /// each report, because "no visit landed" and "visits were never armed" look identical in a
    /// capture otherwise — see the absence-of-a-log-line trap.
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

    /// Not armed, and why. `status` is the raw `CLAuthorizationStatus`.
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

    /// `delay` is how long after the visit edge iOS told us — routinely minutes, which is why the
    /// visit coordinate is never used as an anchor.
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
                    // Recorded because this is an OS-delivered input and a transcript has to carry
                    // what the OS handed over. Never read as an anchor — see `GeofenceVisit`.
                    ("lat", GeofenceLog.num(coordinate.latitude, 5)),
                    ("lon", GeofenceLog.num(coordinate.longitude, 5)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("delay", GeofenceLog.num(reportDelay, 0))
                ]),
            geofenceTag
        )
    }
}
