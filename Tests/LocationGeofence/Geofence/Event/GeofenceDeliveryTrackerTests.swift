@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("GeofenceDeliveryTracker")
struct GeofenceDeliveryTrackerTests {
    private func makeTracker(
        httpClient: BackgroundDeliveryHttpClientMock = BackgroundDeliveryHttpClientMock()
    ) -> (tracker: GeofenceDeliveryTrackerImpl, httpClient: BackgroundDeliveryHttpClientMock) {
        let tracker = GeofenceDeliveryTrackerImpl(httpClient: httpClient, logger: LoggerMock())
        return (tracker, httpClient)
    }

    private func makeMetric(
        geofenceId: String = "geo_1",
        transition: GeofenceTransition = .enter,
        timestamp: Date = Date(timeIntervalSince1970: 1700000000),
        name: String? = nil,
        transitionId: String = "txn_abc"
    ) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: timestamp,
            userId: nil,
            name: name,
            transitionId: transitionId
        )
    }

    // MARK: - Argument shaping

    @Test
    func trackMetric_givenEnterTransition_expectTransitionEventPayload() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let args = httpClient.sendTrackEventReceivedArguments
        #expect(args?.request.eventName == "Geofence Transition")
        #expect(args?.request.userId == "user_42")
        // timestamp rides on the request envelope, not in properties.
        #expect(args?.request.timestamp == Date(timeIntervalSince1970: 1700000000))
        let properties = args?.request.properties ?? [:]
        #expect(properties["geofenceId"] as? String == "geo_1")
        #expect(properties["transition"] as? String == "enter")
        // TESTING-ONLY (geofence-testing branch): the HTTP path uses `trackEventPropertiesForTesting`,
        // which adds `timestamp` to properties (on top of the envelope) for verification.
        #expect(properties["timestamp"] as? String == "2023-11-14T22:13:20.000Z")
        #expect(properties["latitude"] == nil)
        #expect(properties["longitude"] == nil)
        // No name on the metric → property omitted entirely (not sent empty/null).
        #expect(properties["geofenceName"] == nil)
        // transitionId carried through verbatim from the persisted row.
        #expect(properties["transitionId"] as? String == "txn_abc")
    }

    @Test
    func trackMetric_givenName_expectGeofenceNameProperty() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(name: "HQ"), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let properties = httpClient.sendTrackEventReceivedArguments?.request.properties ?? [:]
        #expect(properties["geofenceName"] as? String == "HQ")
    }

    @Test
    func trackMetric_givenExitTransition_expectSameEventNameAndExitProperty() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(transition: .exit), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let args = httpClient.sendTrackEventReceivedArguments
        #expect(args?.request.eventName == "Geofence Transition")
        #expect(args?.request.properties["transition"] as? String == "exit")
    }

    // MARK: - Guard clauses

    @Test
    func trackMetric_givenEmptyUserId_expectFailureAndNoHttpCall() async {
        let (tracker, httpClient) = makeTracker()

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "") { result in
                continuation.resume(returning: result)
            }
        }

        #expect(httpClient.sendTrackEventCallsCount == 0)
        if case .success = result { Issue.record("expected failure for empty userId") }
    }

    // MARK: - Result propagation

    @Test
    func trackMetric_givenHttpFailure_expectFailurePropagated() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in
            completion(.failure(.http(statusCode: 500)))
        }

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "user_42") { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let error) = result {
            #expect(error == .http(statusCode: 500))
        } else {
            Issue.record("expected failure")
        }
    }
}
