import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    func geofenceAdded(id: String, latitude: Double, longitude: Double, radius: Double) {
        debug(
            "Added geofence '\(id)' at lat=\(latitude), lon=\(longitude), radius=\(radius)m",
            geofenceTag
        )
    }

    func geofenceRemoved(id: String) {
        debug(
            "Removed geofence '\(id)'",
            geofenceTag
        )
    }

    func geofenceAllRemoved(count: Int) {
        debug(
            "Removed all geofences (count: \(count))",
            geofenceTag
        )
    }

    func geofenceEntered(id: String, name: String?) {
        let nameText = name.map { " (\($0))" } ?? ""
        info(
            "User entered geofence '\(id)'\(nameText)",
            geofenceTag
        )
    }

    func geofenceExited(id: String, name: String?) {
        let nameText = name.map { " (\($0))" } ?? ""
        info(
            "User exited geofence '\(id)'\(nameText)",
            geofenceTag
        )
    }

    func geofenceDwelled(id: String, name: String?) {
        let nameText = name.map { " (\($0))" } ?? ""
        info(
            "User dwelled in geofence '\(id)'\(nameText)",
            geofenceTag
        )
    }

    func geofenceDuplicateCoordinates(existingId: String, newId: String, latitude: Double, longitude: Double) {
        error(
            "Duplicate geofence coordinates detected. Existing ID '\(existingId)' already uses lat=\(latitude), lon=\(longitude). Skipping new geofence '\(newId)'.",
            geofenceTag,
            nil
        )
    }

    func geofenceLimitExceeded(limit: Int, removedCount: Int) {
        debug(
            "Geofence limit of \(limit) exceeded. Removed \(removedCount) oldest geofence(s).",
            geofenceTag
        )
    }

    func geofenceEventSkippedUserNotIdentified(eventType: String, id: String) {
        debug(
            "Skipping geofence \(eventType) event for '\(id)' because user is not identified",
            geofenceTag
        )
    }

    func geofenceEventSkippedDataPipelineUnavailable(eventType: String, id: String) {
        debug(
            "Skipping geofence \(eventType) event for '\(id)' because DataPipeline is unavailable",
            geofenceTag
        )
    }

    func geofenceRestoredFromStorage(count: Int) {
        debug(
            "Restored \(count) geofence(s) from storage",
            geofenceTag
        )
    }

    func geofenceMonitoringFailed(id: String, error err: Error) {
        error(
            "Geofence monitoring failed for '\(id)'",
            geofenceTag,
            err
        )
    }
}
