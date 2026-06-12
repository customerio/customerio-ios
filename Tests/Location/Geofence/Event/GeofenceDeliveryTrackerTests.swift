@testable import CioInternalCommon
@testable import CioLocation
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
        latitude: Double? = 12.34,
        longitude: Double? = 56.78,
        timestamp: Date = Date(timeIntervalSince1970: 1700000000)
    ) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            userId: nil
        )
    }

    // MARK: - Argument shaping

    @Test
    func trackMetric_givenEnterTransition_expectAndroidWireFormat() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, _, _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let args = httpClient.sendTrackEventReceivedArguments
        #expect(args?.eventName == "CIO Geofence Entered")
        #expect(args?.userId == "user_42")
        let properties = args?.properties ?? [:]
        #expect(properties["geofence_id"] as? String == "geo_1")
        #expect(properties["transition_type"] as? String == "enter")
        #expect(properties["latitude"] as? Double == 12.34)
        #expect(properties["longitude"] as? Double == 56.78)
        #expect(properties["timestamp"] as? Int == 1700000000)
    }

    @Test
    func trackMetric_givenExitTransition_expectExitedEventName() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, _, _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(transition: .exit), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        #expect(httpClient.sendTrackEventReceivedArguments?.eventName == "CIO Geofence Exited")
    }

    @Test
    func trackMetric_givenNilCoordinates_expectOmittedFromProperties() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, _, _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(
                metric: makeMetric(latitude: nil, longitude: nil),
                userId: "user_42"
            ) { _ in continuation.resume() }
        }

        let properties = httpClient.sendTrackEventReceivedArguments?.properties ?? [:]
        #expect(properties["latitude"] == nil)
        #expect(properties["longitude"] == nil)
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
        httpClient.sendTrackEventClosure = { _, _, _, completion in
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
