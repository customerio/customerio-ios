import CioAnalytics
import CioInternalCommon

extension DataPipelineImplementation {
    /// Tracks a geofence transition forwarded via EventBus from `GeofenceEventTracker`
    /// when the row carries no stamped userId (anonymous capture path).
    ///
    /// Mirrors the property shape of the direct-HTTP path so both delivery channels
    /// record the same set of fields. The `TrackEvent.timestamp` is set from
    /// `metric.timestamp` so a flush replayed hours after capture still attributes
    /// the transition to when it happened, not when it was sent.
    func processGeofenceMetricEvent(_ metric: TrackGeofenceMetricEvent) {
        var trackEvent = TrackEvent(event: metric.trackEventName, properties: try? JSON(metric.trackEventProperties))
        trackEvent.timestamp = metric.timestamp.string(format: .iso8601WithMilliseconds)
        analytics.process(event: trackEvent)
    }
}
