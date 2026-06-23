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
        name: String? = nil
    ) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: timestamp,
            userId: nil,
            name: name
        )
    }

    // MARK: - Argument shaping

    @Test
    func trackMetric_givenEnterTransition_expectAndroidWireFormat() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let args = httpClient.sendTrackEventReceivedArguments
        #expect(args?.request.eventName == "geofence_entered")
        #expect(args?.request.userId == "user_42")
        #expect(args?.request.timestamp == Date(timeIntervalSince1970: 1700000000))
        let properties = args?.request.properties ?? [:]
        #expect(properties["geofence_id"] as? String == "geo_1")
        #expect(properties["transition_type"] as? String == "enter")
        #expect(properties["timestamp"] as? Int == 1700000000)
        #expect(properties["latitude"] == nil)
        #expect(properties["longitude"] == nil)
        // No name on the metric → property omitted entirely (not sent empty/null).
        #expect(properties["geofence_name"] == nil)
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
        #expect(properties["geofence_name"] as? String == "HQ")
    }

    @Test
    func trackMetric_givenExitTransition_expectExitedEventName() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(transition: .exit), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        #expect(httpClient.sendTrackEventReceivedArguments?.request.eventName == "geofence_exited")
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
