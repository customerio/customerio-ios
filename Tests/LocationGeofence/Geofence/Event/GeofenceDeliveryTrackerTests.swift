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
        transitionId: String = "txn_abc",
        geosetId: String? = nil,
        metadata: [String: GeofenceMetadataValue]? = nil
    ) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: timestamp,
            userId: "user_1",
            name: name,
            transitionId: transitionId,
            geosetId: geosetId,
            metadata: metadata
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
        #expect(properties["timestamp"] == nil)
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

    @Test
    func trackMetric_givenGeosetId_expectGeosetIdEmittedAsString() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(geosetId: "set_alpha"), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let properties = httpClient.sendTrackEventReceivedArguments?.request.properties ?? [:]
        #expect(properties["geosetId"] as? String == "set_alpha")
    }

    @Test
    func trackMetric_givenNumericGeosetId_expectEmittedAsStringNotNumber() async {
        // A numeric-looking geoset must serialize as a JSON string, not a number, to stay aligned
        // with Android (which also emits it as a string). Guards against re-introducing numeric
        // coercion in trackEventProperties.
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(geosetId: "123"), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let properties = httpClient.sendTrackEventReceivedArguments?.request.properties ?? [:]
        #expect(properties["geosetId"] as? String == "123")
        #expect(properties["geosetId"] as? Int == nil)
    }

    @Test
    func trackMetric_givenMetadata_expectNestedMetadataObjectWithPreservedTypes() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }
        let metadata: [String: GeofenceMetadataValue] = [
            "category": .string("office"), "priority": .int(3), "vip": .bool(true)
        ]

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(metadata: metadata), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let properties = httpClient.sendTrackEventReceivedArguments?.request.properties ?? [:]
        let nested = properties["metadata"] as? [String: Any]
        #expect(nested?["category"] as? String == "office")
        #expect(nested?["priority"] as? Int64 == 3)
        #expect(nested?["vip"] as? Bool == true)
    }

    @Test
    func trackMetric_givenNoMetadata_expectEmptyMetadataObject() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.sendTrackEventClosure = { _, completion in completion(.success(())) }

        await withCheckedContinuation { continuation in
            tracker.trackMetric(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        // Always present as an (empty) object rather than omitted/nil.
        let properties = httpClient.sendTrackEventReceivedArguments?.request.properties ?? [:]
        #expect((properties["metadata"] as? [String: Any])?.isEmpty == true)
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
