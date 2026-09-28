import Foundation

/// Constants used across geofence components.
enum GeofenceConstants {
    /// Region identifier for the Movement Trigger Geofence.
    static let movementTriggerIdentifier = "cio_movement_trigger"

    /// Maximum number of business geofences to monitor.
    /// iOS allows 20 total monitored regions; 1 is reserved for the movement trigger.
    static let maxMonitoredGeofences = 19

    /// Fallback for `localRefreshTriggerRadius` (meters) — the movement-trigger geofence radius and
    /// the ranking-staleness threshold. Server config overrides it.
    static let movementTriggerRadius: Double = 1000

    /// Fallback for `remoteFetchRefreshTriggerRadius` (meters): how far the device must move from the
    /// last fetch anchor before the SDK refetches a fresh nearby set.
    static let serverFetchDistance: Double = 5000

    /// Default `maxMonitoringDistance` (meters) when the server omits it or sends a value below the
    /// trigger radius. Finite so a device far from every geofence doesn't spend OS slots on regions
    /// it can't reach soon; local re-rank adds them as the device approaches.
    static let defaultMaxMonitoringDistance: Double = 1000000 // 1000 km

    /// Sentinel for "no distance cap", used when the server explicitly sends `0`.
    static let noMonitoringDistanceCap: Double = .greatestFiniteMagnitude

    /// Cooldown interval (in seconds) for suppressing duplicate enter/exit events for the same geofence.
    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    /// Staleness interval (in seconds) after which a server sync is considered stale.
    static let staleSyncInterval: TimeInterval = 24 * 60 * 60

    // A long-suspended process's cached fix can be frozen at process start. A movement pass whose
    // cached fix is older than `movementFixMaxAge` requests a fresh one, falling back to the cache
    // after `movementFixRequestTimeout`.
    static let movementFixMaxAge: TimeInterval = 30
    static let movementFixRequestTimeout: TimeInterval = 10

    /// Minimum time between foreground re-arms. locationd's per-fence promotion record can wedge
    /// while a process stays suspended for days; a re-arm rebuilds it and the OS emits a corrective
    /// for any missed crossing. Cold launch already re-arms via adopt.
    static let foregroundRearmInterval: TimeInterval = 6 * 60 * 60

    // Floor on the baseline-heal ambiguity margin (meters): a fix closer than this to the fence
    // edge never synthesizes a crossing, even when it reports better accuracy.
    static let baselineHealMinEdgeMargin: Double = 20

    /// How long after a condition's (re)add the contradiction gate vets its events. The daemon's
    /// belief replays land within a few seconds of the add; the rest is slack for pipeline drain.
    /// Events outside the window (`ConditionReadd.replayWindowCovers`) are never gated, so a normal
    /// crossing is never delayed or refused.
    static let contradictionGateReplayWindow: TimeInterval = 10

    // Bounds for server config: a positive out-of-range value clamps, a non-positive one falls
    // back. `maxMonitoringDistance` needs no upper bound, and falls back to the default when below
    // the trigger radius.
    static let minLocalRefreshRadius: Double = 100
    static let maxLocalRefreshRadius: Double = 5000
    static let minRemoteFetchRefreshExpiry: TimeInterval = 60 // 1 minute
    static let maxRemoteFetchRefreshExpiry: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    static let minDuplicateEventsExpiry: TimeInterval = 60 // 1 minute
    static let maxDuplicateEventsExpiry: TimeInterval = 24 * 60 * 60 // 24 hours

    // Safety net on workspace-defined `metadata`, which the server already validates: only stops a
    // runaway payload bloating a background request. Generous so a future server increase can't
    // make the SDK drop valid data; per-value size is left to the server.
    static let maxMetadataCount = 100
    static let maxMetadataPayloadBytes = 100 * 1024 // ~20× the server's 5 KB total

    /// Floor on the movement trigger's radius once polygons shrink it: below this the OS promotes
    /// crossings too unreliably to be worth a wake, so a nearer boundary is reached late.
    static let polygonWakeMinRadius: Double = 100
}
