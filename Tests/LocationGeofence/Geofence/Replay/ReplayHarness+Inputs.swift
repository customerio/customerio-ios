@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    /// Only a `bus` fix is an arrival. Replaying a cache read as one can consume a rearm flag and
    /// start a sync the drive never ran.
    func feedFix(latitude: Double, longitude: Double, accuracy: Double?, age: TimeInterval, source: GeofenceLog.FixSource) {
        let location = LocationData(latitude: latitude, longitude: longitude)

        guard source != .bus else {
            // Not cached as last-known: that would anchor a post-login sync on a stale first fix.
            trigger.onLocationAcquired(location)
            return
        }

        // Everything else is a read, already on the pull timeline (see `ReplayFixProvider`).
    }

    func loadPulledFixes(
        stimuli: [TimeInterval],
        samples: [ReplayFixProvider.CachedRead],
        carried: [ReplayFixProvider.CachedRead] = []
    ) {
        fixes.load(stimuli: stimuli, samples: samples, carried: carried)
    }

    func pulledFix(latitude: Double, longitude: Double, accuracy: Double, age: TimeInterval, at: TimeInterval) -> ReplayFixProvider.CachedRead {
        ReplayFixProvider.CachedRead(
            at: at,
            location: LocationData(latitude: latitude, longitude: longitude),
            accuracy: accuracy,
            age: age
        )
    }

    func emptyPull(at: TimeInterval) -> ReplayFixProvider.CachedRead {
        ReplayFixProvider.CachedRead(at: at, location: nil, accuracy: 0, age: 0)
    }

    /// Queued up front, not at its timestamp: a fixture is stamped on arrival, a round trip after its
    /// fetch.
    func enqueueFetch(bodyJSON: String) throws {
        let envelope = #"{"geofences":\#(bodyJSON)}"#
        let response = try JSONDecoder().decode(GeofenceApiResponse.self, from: Data(envelope.utf8))
        fetchQueue.append(.success(response))
        installFetchQueue()
    }

    func enqueueFetchFailure(why: String?) {
        // Mirrors every token `diagnosticToken` can emit.
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
                // Answered anyway: an unanswered completion hangs the coordinator silently.
                completion(.failure(.transport))
                return
            }
            // Before the hop: after it the clock may have moved on and the recorded answer be dropped.
            let askedAt = self.clock.givenNow.timeIntervalSince(self.epoch)
            // Not `assumeIsolated`: the coordinator calls this from its own executor, so it would trap.
            Task { @MainActor in
                self.fetchCount += 1
                guard !self.fetchQueue.isEmpty else {
                    self.starvedFetchCount += 1
                    completion(.failure(.transport))
                    return
                }
                let answer = self.fetchQueue.removeFirst()
                await self.gate.park(at: self.gate.fetchAnswerTime(after: askedAt), what: "api.fetch") {
                    completion(answer)
                }
            }
        }
    }

    func fetchAccounting() -> String? {
        // With no fixture enqueued there is no stub; only the mock counts fetches.
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

    func pullAccounting() -> String? {
        fixes.pullAccounting()
    }
}

extension GeofenceLog.FixSource {
    /// Only `bus` arrives; every other `location.fix`, `resolver` included, is the SDK reading.
    var isArrival: Bool {
        switch self {
        case .bus: return true
        case .managerCache, .resolver, .freshRequest, .gate, .synthetic, .none: return false
        }
    }
}
