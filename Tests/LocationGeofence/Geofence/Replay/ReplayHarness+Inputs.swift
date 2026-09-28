@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    /// Hands the SDK a fix that *arrived*, as the drive recorded it.
    ///
    /// **A pull is not an arrival.** `manager_cache` records are the SDK reading
    /// `CLLocationManager.location`; they are loaded into `ReplayFixProvider` and answered when the
    /// SDK reads. Only a `bus` fix is an arrival: in production only `GeofenceModuleState`'s
    /// `LocationAcquiredEvent` observer calls `onLocationAcquired`. Replaying a read as an arrival
    /// can consume a rearm flag and start a sync the drive never ran.
    func feedFix(latitude: Double, longitude: Double, accuracy: Double?, age: TimeInterval, source: GeofenceLog.FixSource) {
        let location = LocationData(latitude: latitude, longitude: longitude)

        // A bus fix is a position the SDK is *told*, not one it holds. `LocationAcquiredEvent`
        // carries only latitude and longitude (hence `accuracy` is optional) and goes straight to
        // the trigger; it never reaches `bestKnownFix()` or the resolver's `CLLocationManager`.
        guard source != .bus else {
            // Not cached as the module's last-known either: in the captured composition
            // `getLastKnownLocation()` answers nil, and caching here would anchor a post-login sync
            // on a stale first fix instead of the arm-then-next-fix path production takes.
            trigger.onLocationAcquired(location)
            return
        }

        // Everything else is a read, already on the pull timeline (see `ReplayFixProvider`).
    }

    /// Loads every fix the SDK *pulled* during the drive, before the first stimulus runs. See
    /// `ReplayFixProvider`.
    func loadPulledFixes(
        stimuli: [TimeInterval],
        samples: [ReplayFixProvider.CachedRead],
        carried: [ReplayFixProvider.CachedRead] = []
    ) {
        fixes.load(stimuli: stimuli, samples: samples, carried: carried)
    }

    /// Builds a recorded cache read for `loadPulledFixes`. No timestamp: the drive recorded how
    /// stale the position was, and the provider dates it when the SDK actually looks.
    func pulledFix(latitude: Double, longitude: Double, accuracy: Double, age: TimeInterval, at: TimeInterval) -> ReplayFixProvider.CachedRead {
        ReplayFixProvider.CachedRead(
            at: at,
            location: LocationData(latitude: latitude, longitude: longitude),
            accuracy: accuracy,
            age: age
        )
    }

    /// A read the drive recorded as finding nothing (`prov=none`).
    func emptyPull(at: TimeInterval) -> ReplayFixProvider.CachedRead {
        ReplayFixProvider.CachedRead(at: at, location: nil, accuracy: 0, age: 0)
    }

    /// Queues the API answers the drive recorded, in the order it recorded them.
    ///
    /// **Queued up front, not installed at their timestamp.** A fixture is stamped when the
    /// response *arrived*, one round trip after the fetch that asked for it, so installing it at
    /// that timestamp is always too late. The Android harness does the same.
    ///
    /// Decoded by the **shipping decoder**, so the fixture tracks the wire format.
    func enqueueFetch(bodyJSON: String) throws {
        let envelope = #"{"geofences":\#(bodyJSON)}"#
        let response = try JSONDecoder().decode(GeofenceApiResponse.self, from: Data(envelope.utf8))
        fetchQueue.append(.success(response))
        installFetchQueue()
    }

    /// Queues a failure the way the drive's network produced one.
    ///
    /// `why` is the capture's own token, so a drive that lost the network mid-route replays as the
    /// same failure the SDK actually saw rather than a generic one.
    func enqueueFetchFailure(why: String?) {
        // Every token `diagnosticToken` can emit, mapped back, so a recorded `why` replays as the
        // same failure.
        let error: GeofenceApiError = switch why {
        case "transport": .transport
        case "decoding": .decoding
        case "invalid_request": .invalidRequest
        case "missing_api_host": .missingApiHost
        case "missing_cdp_api_key": .missingCdpApiKey
        case let token? where token.hasPrefix("http_"):
            .http(statusCode: Int(token.dropFirst("http_".count)) ?? 0)
        default: .transport
        }
        fetchQueue.append(.failure(error))
        installFetchQueue()
    }

    private func installFetchQueue() {
        api.fetchNearbyGeofencesClosure = { [weak self] _, _, completion in
            guard let self else {
                // Only after the test. Answered anyway: an unanswered completion suspends the
                // coordinator's continuation forever, silently.
                completion(.failure(.transport))
                return
            }
            // Sampled before the hop: it must be the moment the SDK asked (`DateUtilStub` is
            // thread-safe). After the hop the main actor may have moved the clock on, and
            // `nextAnswer` would discard the recorded answer for the fallback without any report.
            let askedAt = self.clock.givenNow.timeIntervalSince(self.epoch)
            // The queue, counters and gate are main-actor state. The coordinator calls this from
            // its own executor, so `assumeIsolated` would trap; the hop is required.
            Task { @MainActor in
                self.fetchCount += 1
                guard !self.fetchQueue.isEmpty else {
                    self.starvedFetchCount += 1
                    // Reported by `fetchAccounting()`; answered so it is not also a hang.
                    completion(.failure(.transport))
                    return
                }
                let answer = self.fetchQueue.removeFirst()
                // Parked until the moment the drive recorded the response arriving.
                await self.gate.park(at: self.gate.fetchAnswerTime(after: askedAt), what: "api.fetch") {
                    completion(answer)
                }
            }
        }
    }

    /// Whether the replay asked for exactly the responses the drive recorded. Fixtures are queued
    /// up front, so a replay that syncs a different number of times would otherwise diverge quietly.
    func fetchAccounting() -> String? {
        // The stub only exists once a fixture is enqueued; with none, only the mock counts fetches.
        if fetchQueue.isEmpty, fetchCount == 0, api.fetchNearbyGeofencesCallsCount > 0 {
            return "\(api.fetchNearbyGeofencesCallsCount) fetch(es) with no recorded fixture — the drive captured no response for them"
        }
        if starvedFetchCount > 0 {
            return "\(fetchCount) fetches, \(starvedFetchCount) unanswered — replay synced more often than the drive"
        }
        if !fetchQueue.isEmpty {
            return "\(fetchCount) fetches, \(fetchQueue.count) fixture(s) unused — replay synced less often than the drive"
        }
        return nil
    }

    /// Whether the SDK read the OS cache at moments the drive actually recorded one.
    func pullAccounting() -> String? {
        fixes.pullAccounting()
    }
}

extension GeofenceLog.FixSource {
    /// Whether a recorded fix reached the SDK because it arrived, or because the SDK went and read it.
    ///
    /// Only `bus` arrives (`GeofenceModuleState`'s `LocationAcquiredEvent` observer). Every other
    /// `location.fix` is `bestKnownFixDetail()` reading — `resolver` included, which only means the
    /// resolver's fix was newer than the cache — so it belongs on the pull timeline.
    var isArrival: Bool {
        switch self {
        case .bus: return true
        case .managerCache, .resolver, .freshRequest, .gate, .synthetic, .none: return false
        }
    }
}
