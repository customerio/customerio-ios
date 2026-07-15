import CioAnalytics
import CioInternalCommon

extension DataPipelineImplementation {
    /// Tracks a geofence transition forwarded via EventBus from `GeofenceEventTracker`'s flush.
    /// `userId` and `timestamp` are pinned from the transition's snapshot so a delayed replay
    /// attributes to the right person and time. `process(event:)` preserves both — `track` would
    /// overwrite userId with the current identity.
    func processGeofenceMetricEvent(_ metric: TrackGeofenceMetricEvent) {
        var trackEvent = TrackEvent(event: metric.trackEventName, properties: try? JSON(metric.trackEventProperties))
        trackEvent.timestamp = metric.timestamp.string(format: .iso8601WithMilliseconds)
        trackEvent.userId = metric.userId
        analytics.process(event: trackEvent)
    }
}
