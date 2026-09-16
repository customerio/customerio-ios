@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    /// Hands the SDK a fix that *arrived*, as the drive recorded it.
    ///
    /// `age` reconstructs the fix's own timestamp against virtual time, so the freshness rules that
    /// read it (heal fix-age guard, movement staleness) see the same age the phone did.
    ///
    /// **A pull is not an arrival.** `manager_cache` records are the SDK reading
    /// `CLLocationManager.location` — the SDK asking a question, not the world telling it
    /// something. They are loaded into `ReplayFixProvider` as the cache's timeline and answered
    /// when the SDK reads. Only a fix the SDK *requested and received* is an arrival, and only an
    /// arrival fires `LocationAcquiredEvent` in production (`GeofenceModuleState` observes that
    /// event and nothing else calls `onLocationAcquired`).
    ///
    /// Treating every read as an arrival is what this used to do, and on the 2026-09-09 drive that
    /// meant 43 arrival events against production's zero — 43 chances to consume a rearm flag and
    /// drive a sync the drive never ran.
    func feedFix(latitude: Double, longitude: Double, accuracy: Double?, age: TimeInterval, source: GeofenceLog.FixSource) {
        let location = LocationData(latitude: latitude, longitude: longitude)

        // A bus fix is not a position the SDK *holds*, it is one it was *told*.
        //
        // `LocationAcquiredEvent` carries a `LocationData` — latitude and longitude, nothing else —
        // and `GeofenceModuleState` hands it straight to the trigger. It never reaches
        // `bestKnownFix()`, which only ever chooses between the `CLLocationManager` cache and the
        // resolver, and it never reaches the resolver's own `CLLocationManager`. Writing it into
        // the cache armed one production leaves empty, and answering the resolver with it satisfied
        // a one-shot request that in production only CoreLocation can satisfy.
        //
        // It also has no accuracy to carry, which is why `accuracy` is optional: `LocationData` has
        // no such field, so the SDK does not know it either. A replay that demanded one was
        // demanding something no capture can contain.
        guard source != .bus else {
            // NOT cached as the module's last-known. `LocationServices.getLastKnownLocation()` is a
            // store the *Location* module owns, and in the composition every drive was captured
            // from it answers nil — the sample app leaves it uninitialised. The captures prove it:
            // `refreshIfPossible` consults it only when no registration center exists, and every
            // time a drive reaches that branch it logs `movement.rearmed why=first_run`, which fires
            // only on the arm-then-next-fix path taken when the anchor was nil.
            //
            // Caching here made the store more durable than production's and short-circuited that
            // path. Invisible until a drive signed out — the only other moment the registration
            // center is nil — where it anchored the post-login sync on the session's FIRST fix and
            // ranked from a position 6.5 km stale (2026-09-12, ios-iphone15-drive4-0202).
            trigger.onLocationAcquired(location)
            return
        }

        // Pulled fixes are pre-loaded as a timeline (see `ReplayFixProvider`), so replaying one as
        // a stimulus would double-count it. The read answers from the timeline on its own.
        guard source.isArrival else { return }

        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy ?? -1,
            verticalAccuracy: -1,
            timestamp: clock.givenNow.addingTimeInterval(-age)
        )

        // Satisfies a pending one-shot request the way a returning CoreLocation fix would, and is
        // retained by the real resolver — which is what makes it win over a staler cache read at
        // the SDK's own `bestKnownFix()`, rather than the harness deciding that.
        monitor.movementFixResolver.handleDeliveredFix(fix)
        // What fires `LocationAcquiredEvent` in production; the trigger consumes it only when
        // something armed for it.
        trigger.onLocationAcquired(location)
    }

    /// Loads every fix the SDK *pulled* during the drive, before the first stimulus runs.
    ///
    /// See `ReplayFixProvider`: a pulled fix is ambient OS state read at an arbitrary moment, not
    /// an event delivered at a known one, and the record is stamped at the read.
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
    /// **Queued up front, not installed at their timestamp.** `api.fetch.result` is written when
    /// the *response arrives*, so its position in the capture is always one round-trip later than
    /// the fetch that asked for it. Installing a fixture at that timestamp puts it in place after
    /// the SDK has already asked — on the 2026-09-09 iPhone drive the first sync fired at 3.288s
    /// and its fixture sat at 3.963s, so the fetch went to an unstubbed mock, nothing completed,
    /// and a 141-record drive replayed as zero registrations and zero transitions. Android hit the
    /// same wall and resolved it the same way; the two harnesses stay aligned deliberately.
    ///
    /// The bodies are handed to the **shipping decoder** rather than built field by field: a
    /// hand-built response would silently stop matching the wire format the moment a field is
    /// added, and decoding is itself part of what the drive exercised.
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
        // Every token `diagnosticToken` can emit, mapped back. Defaulting the unhandled ones onto
        // `.transport` made a drive that recorded `why=http_500` replay as `why=transport`, and the
        // mismatch reads as an SDK behaviour change rather than a gap in this switch.
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
                // Reachable only once the harness is gone, i.e. after the test. Answered anyway:
                // an unanswered completion suspends the coordinator's `withCheckedContinuation`
                // forever, and the generated mock retains the closure so the runtime never even
                // reports a leaked continuation.
                completion(.failure(.transport))
                return
            }
            // Sampled here, before the hop, because it must be the moment the SDK *asked*.
            // `DateUtilStub` guards its storage, so an off-actor read is safe. Read after the hop
            // instead, it samples a clock the main actor may already have stepped forward, and
            // `nextAnswer` then discards every recorded answer behind that inflated moment — the
            // drive's real round trip silently collapses to the modelled fallback, with the
            // fixture still consumed in order so `fetchAccounting()` reports nothing wrong.
            let askedAt = self.clock.givenNow.timeIntervalSince(self.epoch)
            // Everything else touches main-actor state: the queue, both counters, the gate. The
            // coordinator awaits this closure from its own executor, so `assumeIsolated` would
            // trap the test process — the hop is required, and counting and dequeuing outside it
            // raced two overlapping syncs on a plain Array.
            Task { @MainActor in
                self.fetchCount += 1
                guard !self.fetchQueue.isEmpty else {
                    self.starvedFetchCount += 1
                    // A starved fetch is a finding `fetchAccounting()` already reports. It must
                    // not also be a hang, so it is answered rather than dropped.
                    completion(.failure(.transport))
                    return
                }
                let answer = self.fetchQueue.removeFirst()
                // Parked, not answered. The response arrives when the drive recorded it arriving,
                // and the SDK spends that round trip mid-sync exactly as the phone did.
                await self.gate.park(at: self.gate.fetchAnswerTime(after: askedAt), what: "api.fetch") {
                    completion(answer)
                }
            }
        }
    }

    /// Whether the replay asked for exactly the responses the drive recorded.
    ///
    /// Worth reporting on its own: fixtures are queued up front, so a replay that syncs a different
    /// number of times still gets plausible-looking answers and diverges quietly. This is the
    /// signal that the divergence is upstream of any decision the matcher grades.
    func fetchAccounting() -> String? {
        // The stub only exists once a fixture has been enqueued, so a scenario with none leaves
        // the mock's own default in place: the SDK's fetches are recorded by the mock but none of
        // the counters here move, and every check below reads clean. Ask the mock instead.
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
    /// Only the first is an event. `managerCache` and `gate` are reads of a position the OS already
    /// held — the SDK pulled them, nothing was delivered — so replaying them as deliveries invents
    /// arrivals the drive never had. `synthetic` and `none` describe a record with no fix behind it
    /// at all.
    var isArrival: Bool {
        switch self {
        // `.bus` never reaches this: `feedFix` routes it to the trigger and returns. Left `true`
        // because it *is* an arrival — it simply arrives somewhere else.
        case .bus, .resolver, .freshRequest: return true
        case .managerCache, .gate, .synthetic, .none: return false
        }
    }
}
