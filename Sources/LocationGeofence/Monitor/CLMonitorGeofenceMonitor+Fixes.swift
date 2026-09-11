import CioInternalCommon
import CoreLocation
import Foundation

/// Cached-fix reads for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable (same convention as `+Registration`).
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Newest usable fix across the auth manager's cache and the resolver's requested fixes.
    /// The manager's cache can freeze at process start on a long-suspended process, so a fresher
    /// resolver fix must win wherever cached position is read.
    func bestKnownFix() -> CLLocation? {
        bestKnownFixDetail()?.fix
    }

    /// The same choice, but reporting which source won.
    ///
    /// Worth carrying into diagnostics: a resolver fix was requested and delivered, while the
    /// manager's cache is whatever the OS last happened to have — and on a long-suspended process
    /// that can be hours old. Both produce a coordinate; only one of them means anything.
    func bestKnownFixDetail() -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        let selected = selectFix()
        // Every cache read is an input and is logged, repeated or not.
        logger.geofenceLocationFix(selected?.fix, source: selected?.source ?? .none, now: dateUtil.now)
        return selected
    }

    private func selectFix() -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        let cached = authManager.currentLocation.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
        guard let resolved = movementFixResolver.latestFix else {
            return cached.map { ($0, .managerCache) }
        }
        guard let cached else { return (resolved, .resolver) }
        return resolved.timestamp > cached.timestamp ? (resolved, .resolver) : (cached, .managerCache)
    }

    /// Records an OS-delivered crossing together with the fix the SDK will attach to it.
    ///
    /// Lives here rather than inline at the event handler because this is where the full
    /// `CLLocation` and its provenance are known — and because the handler is already at the
    /// file-length limit.
    func logReceivedCallback(identifier: String, transition: GeofenceTransition, eventDate: Date?) {
        let detail = bestKnownFixDetail()
        logger.geofenceCallbackReceived(
            identifier: identifier,
            transition: transition,
            fix: detail?.fix,
            source: detail?.source ?? .none,
            eventDate: eventDate,
            now: dateUtil.now
        )
    }

    /// Records a crossing the dedup baseline discarded, and why.
    ///
    /// Same reason `logReceivedCallback` lives here: the handler is at the file-length limit. And
    /// the same reason it exists at all — CLMonitor delivers a crossing more than once (a field
    /// drive saw every one arrive twice, 8-10 ms apart with identical fixes), and the duplicate is
    /// absorbed by the baseline. Without this the discard is invisible, so `os.callback.received`
    /// reads as a crossing count when it is really twice that, and a callback that vanishes here
    /// cannot be told apart from the OS never delivering one.
    ///
    /// `.deliver` logs nothing: it is not a discard.
    func logDiscardedCallback(identifier: String, transition: GeofenceTransition, outcome: GeofenceMonitorEventOutcome) {
        guard let reason = outcome.diagnosticReason else { return }
        logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: reason)
    }

    /// Internal (not private) only because it lives in a separate file from its callers.
    func currentLocationData() -> LocationData? {
        guard let location = bestKnownFix() else { return nil }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// Whether the device is inside the circle per the last known location; `nil` without a usable
    /// fix. No accuracy padding: a wrong guess costs one corrective event, absorbed by the baseline.
    func isDeviceInside(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool? {
        guard let location = bestKnownFix() else { return nil }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }
}
