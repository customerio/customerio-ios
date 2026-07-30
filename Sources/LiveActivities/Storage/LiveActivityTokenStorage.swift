import Foundation

/// Persists Live Activity token-registration state so unchanged tokens are not re-sent across
/// app launches.
///
/// Several kinds of entry share this store, distinguished by their key:
/// - push-to-start dedup signature, keyed by activity type — value `"<deviceToken>|<pushToStartToken>|<userId>"`.
/// - per-instance dedup signature, keyed by `"instance:<instanceUUID>"` — value `"<deviceToken>|<instanceToken>"`.
/// - persisted push-to-start token value, keyed by `"ptsvalue:<activityType>"` — value `"<attributesType>|<pushToStartToken>"`.
/// The registrar skips a registration whose stored signature is unchanged; a new token, user, or
/// device yields a new signature and re-registers. The persisted token value lets the registrar
/// re-seed and register a push-to-start token on a launch where ActivityKit does not re-yield it.
///
/// The store is a plain keyed string map; all key-namespacing policy lives in the registrar.
protocol LiveActivityTokenStorage {
    /// The last stored value for `activityType` (a signature or a persisted token), or `nil`.
    func registrationSignature(activityType: String) -> String?
    /// Record `signature` as the last value for `activityType`.
    func setRegistrationSignature(activityType: String, signature: String)
    /// Remove the stored value for a single `activityType` (e.g. when an instance ends).
    func clearRegistrationSignature(activityType: String)
    /// All keys currently held, so the registrar can seed persisted push-to-start tokens at launch
    /// and clear dedup signatures selectively (preserving persisted tokens) on reset.
    func allRegistrationKeys() -> [String]
    /// Remove all stored entries (e.g. full teardown), forcing re-registration.
    func clearAll()

    /// Whether a still-fresh `delivered` dedup marker exists for `deliveryId` (reported less than
    /// `ttl` ago). Markers older than `ttl` are pruned lazily (once per process) before answering,
    /// so the delivery history stays bounded. Delivery markers live in their own storage map, so
    /// registration-signature lookups never parse delivery history.
    func hasFreshDeliveredMarker(_ deliveryId: String, ttl: TimeInterval) -> Bool
    /// Record a `delivered` dedup marker for `deliveryId`, timestamped `date` (enables TTL expiry).
    func setDeliveredMarker(_ deliveryId: String, at date: Date)
    /// Atomically dedup a `delivered` receipt: if no fresh marker (within `ttl`) exists for
    /// `deliveryId`, record one timestamped `date` and return `true` (the caller should report);
    /// otherwise return `false`. The check-and-set runs under a single lock so concurrent pushes
    /// carrying the same delivery id can't both pass the check and double-report.
    func markDeliveredIfFresh(_ deliveryId: String, ttl: TimeInterval, at date: Date) -> Bool

    /// Returns the CIO instance id mapped to a system `Activity.id`, creating and persisting one
    /// via `orCreate` if none exists yet. Atomic: concurrent callers (a local `start` and the
    /// registration observer picking up the same activity) resolve to a single id. Persisting the
    /// mapping lets the observer recover a locally-started activity's id after a relaunch, where the
    /// minted id is no longer in memory and — for non-`CIOActivityAttribute` types — is not in the
    /// activity's attributes either.
    func resolveInstanceId(forActivityId activityId: String, orCreate: () -> String) -> String
    /// Remove the `Activity.id` → instance id mapping (on activity end).
    func clearInstanceId(forActivityId activityId: String)
}
