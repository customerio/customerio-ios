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

    /// Default `maxMonitoringDistance` (meters) applied when the server omits the field — which it
    /// does today. A finite cap (not "unlimited") so a device far from a workspace's geofences (e.g.
    /// in the US with geofences in Europe) doesn't burn OS slots on regions it can't reach soon;
    /// local re-rank re-adds them as the device approaches. The server can send an explicit `0` to
    /// disable the cap (mapped to `noMonitoringDistanceCap`).
    static let defaultMaxMonitoringDistance: Double = 1000000 // 1000 km

    /// Sentinel for "no distance cap" — every candidate registers regardless of distance. Used when
    /// the server explicitly sends `0`.
    static let noMonitoringDistanceCap: Double = .greatestFiniteMagnitude

    /// Cooldown interval (in seconds) for suppressing duplicate enter/exit events for the same geofence.
    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    /// Staleness interval (in seconds) after which a server sync is considered stale.
    static let staleSyncInterval: TimeInterval = 24 * 60 * 60

    // Movement passes act on the device's CURRENT position (re-center the trigger, measure
    // displacement for the refetch tier), but a long-suspended process's cached fix can be frozen
    // at process start. A cached fix older than `movementFixMaxAge` triggers a one-shot fresh-fix
    // request; after `movementFixRequestTimeout` the pass falls back to the cached fix.
    static let movementFixMaxAge: TimeInterval = 30
    static let movementFixRequestTimeout: TimeInterval = 10

    /// Minimum time between foreground re-arms of the armed conditions. locationd's per-fence
    /// promotion record can wedge while a process stays suspended for days (observed in field:
    /// a fence unpromoted for hours on precise fixes); a re-arm rebuilds the record and the OS
    /// emits a corrective for any crossing it missed. Cold launch already re-arms via adopt —
    /// this covers processes that live for days without one.
    static let foregroundRearmInterval: TimeInterval = 6 * 60 * 60

    // Floor on the baseline-heal ambiguity margin (meters): a fix closer than this to the fence
    // edge never synthesizes a crossing, even when it reports better accuracy.
    static let baselineHealMinEdgeMargin: Double = 20

    /// How long after a condition's (re)add the contradiction gate vets its events. The daemon's
    /// belief replays land 0.003–3.3 s after the add (measured across every reproduction); the
    /// window adds slack for pipeline-drain latency. Events dated outside the window — before the
    /// re-add began or beyond this bound after it (see `ConditionReadd.replayWindowCovers`) — are
    /// never gated, so a normal crossing is never delayed by a fix request nor at any risk of refusal.
    static let contradictionGateReplayWindow: TimeInterval = 10

    // Sane bounds the SDK coerces server config into, so a misconfigured backend can't push
    // monitoring into a pathological state: a positive out-of-range value clamps to the nearest
    // bound; a non-positive value falls back. (`maxMonitoringDistance` needs no upper bound — a
    // huge value just means "no cap" — and is separately disabled when below the trigger radius.)
    static let minLocalRefreshRadius: Double = 100
    static let maxLocalRefreshRadius: Double = 5000
    static let minRemoteFetchRefreshExpiry: TimeInterval = 60 // 1 minute
    static let maxRemoteFetchRefreshExpiry: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    static let minDuplicateEventsExpiry: TimeInterval = 60 // 1 minute
    static let maxDuplicateEventsExpiry: TimeInterval = 24 * 60 * 60 // 24 hours

    // Safety net on workspace-defined `metadata`: the server already validates them (they arrive
    // pre-validated in the nearby response), so these only stop a runaway payload from bloating a
    // background request. Set generously ahead of the server so a future increase can't make the SDK
    // drop valid data; per-value size is left to the server.
    static let maxMetadataCount = 100
    static let maxMetadataPayloadBytes = 100 * 1024 // ~20× the server's 5 KB total

    /// Floor on the movement trigger's radius once polygons shrink it: below this the OS promotes
    /// crossings too unreliably to be worth a wake, so a nearer boundary is reached late.
    static let polygonWakeMinRadius: Double = 100
}
