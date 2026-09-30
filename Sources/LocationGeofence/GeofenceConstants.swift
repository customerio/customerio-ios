import Foundation

enum GeofenceConstants {
    static let movementTriggerIdentifier = "cio_movement_trigger"

    /// iOS allows 20 monitored regions; 1 is reserved for the movement trigger.
    static let maxMonitoredGeofences = 19

    /// Fallback for `localRefreshTriggerRadius` (m): trigger radius and ranking-staleness threshold.
    static let movementTriggerRadius: Double = 1000

    /// Fallback for `remoteFetchRefreshTriggerRadius` (m).
    static let serverFetchDistance: Double = 5000

    /// Default `maxMonitoringDistance` (m) when omitted or below the trigger radius. Server `0` means
    /// no cap (`noMonitoringDistanceCap`), not this.
    static let defaultMaxMonitoringDistance: Double = 1000000 // 1000 km

    static let noMonitoringDistanceCap: Double = .greatestFiniteMagnitude

    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    static let staleSyncInterval: TimeInterval = 24 * 60 * 60

    // A long-suspended process's cached fix can be frozen at process start, so movement passes
    // request a fresh one past this age.
    static let movementFixMaxAge: TimeInterval = 30
    static let movementFixRequestTimeout: TimeInterval = 10

    /// Minimum time between foreground re-arms, which rebuild OS fence state that can wedge while the
    /// process stays suspended for days.
    static let foregroundRearmInterval: TimeInterval = 6 * 60 * 60

    // A fix closer than this to the edge never synthesizes a crossing, whatever its accuracy.
    static let baselineHealMinEdgeMargin: Double = 20

    /// How long after a condition's (re)add the contradiction gate vets its events. Events outside
    /// it are never gated.
    static let contradictionGateReplayWindow: TimeInterval = 10

    // Server config bounds: a positive out-of-range value clamps, a non-positive one falls back.
    static let minLocalRefreshRadius: Double = 100
    static let maxLocalRefreshRadius: Double = 5000
    static let minRemoteFetchRefreshExpiry: TimeInterval = 60 // 1 minute
    static let maxRemoteFetchRefreshExpiry: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    static let minDuplicateEventsExpiry: TimeInterval = 60 // 1 minute
    static let maxDuplicateEventsExpiry: TimeInterval = 24 * 60 * 60 // 24 hours

    // Runaway-payload guard only; the server validates `metadata`. Kept generous so a server limit
    // increase can't make the SDK drop valid data.
    static let maxMetadataCount = 100
    static let maxMetadataPayloadBytes = 100 * 1024 // ~20× the server's 5 KB total

    /// Floor on the polygon-shrunk trigger radius: the OS reports smaller crossings unreliably.
    static let polygonWakeMinRadius: Double = 100
}
