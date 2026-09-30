import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    // MARK: - Visits

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

    /// `delay`: seconds from the visit edge to iOS reporting it.
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
                    ("lat", GeofenceLog.num(coordinate.latitude, 5)),
                    ("lon", GeofenceLog.num(coordinate.longitude, 5)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("delay", GeofenceLog.num(reportDelay, 0))
                ]),
            geofenceTag
        )
    }
}
