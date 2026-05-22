@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceDeliveryTracker")
struct GeofenceDeliveryTrackerTests {
    private func makeContextStore(host: String? = "cdp.customer.io/v1") -> BackgroundDeliveryContextStore {
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if let host { store.setApiHost(host) }
        return store
    }

    private func makeTracker(
        contextStore: BackgroundDeliveryContextStore? = nil,
        httpClient: HttpClientMock = HttpClientMock()
    ) -> (tracker: GeofenceDeliveryTrackerImpl, httpClient: HttpClientMock) {
        let tracker = GeofenceDeliveryTrackerImpl(
            httpClient: httpClient,
            contextStore: contextStore ?? makeContextStore(),
            logger: LoggerMock()
        )
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
            timestamp: timestamp
        )
    }

    private func decodeBody(_ data: Data?) -> [String: Any]? {
        guard let data = data,
              let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return any as? [String: Any]
    }

    // MARK: - Request shape

    @Test
    func deliver_givenEnterTransition_expectAndroidWireFormat() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.requestClosure = { _, onComplete in onComplete(.success(Data())) }

        await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let params = httpClient.requestReceivedArguments?.params
        let body = decodeBody(params?.body)
        #expect(body?["event"] as? String == "GeoFence Entered")
        #expect(body?["userId"] as? String == "user_42")
        let properties = body?["properties"] as? [String: Any]
        #expect(properties?["geofence_id"] as? String == "geo_1")
        #expect(properties?["transition_type"] as? String == "enter")
        #expect(properties?["latitude"] as? Double == 12.34)
        #expect(properties?["longitude"] as? Double == 56.78)
        #expect(properties?["timestamp"] as? Int == 1700000000)
        #expect(params?.url.absoluteString == "https://cdp.customer.io/v1/track")
    }

    @Test
    func deliver_givenExitTransition_expectExitedEventName() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.requestClosure = { _, onComplete in onComplete(.success(Data())) }

        await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(transition: .exit), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let body = decodeBody(httpClient.requestReceivedArguments?.params.body)
        #expect(body?["event"] as? String == "GeoFence Exited")
    }

    @Test
    func deliver_givenNilCoordinates_expectOmittedFromProperties() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.requestClosure = { _, onComplete in onComplete(.success(Data())) }

        await withCheckedContinuation { continuation in
            tracker.deliver(
                metric: makeMetric(latitude: nil, longitude: nil),
                userId: "user_42"
            ) { _ in continuation.resume() }
        }

        let properties = decodeBody(httpClient.requestReceivedArguments?.params.body)?["properties"] as? [String: Any]
        #expect(properties?["latitude"] == nil)
        #expect(properties?["longitude"] == nil)
    }

    @Test
    func deliver_givenEUApiHost_expectEUUrl() async {
        let (tracker, httpClient) = makeTracker(contextStore: makeContextStore(host: "cdp-eu.customer.io/v1"))
        httpClient.requestClosure = { _, onComplete in onComplete(.success(Data())) }

        await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let url = httpClient.requestReceivedArguments?.params.url.absoluteString
        #expect(url == "https://cdp-eu.customer.io/v1/track")
    }

    @Test
    func deliver_givenSchemeQualifiedHost_expectSchemeNotDuplicated() async {
        let (tracker, httpClient) = makeTracker(contextStore: makeContextStore(host: "https://cdp.customer.io/v1"))
        httpClient.requestClosure = { _, onComplete in onComplete(.success(Data())) }

        await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "user_42") { _ in
                continuation.resume()
            }
        }

        let url = httpClient.requestReceivedArguments?.params.url.absoluteString
        #expect(url == "https://cdp.customer.io/v1/track")
    }

    // MARK: - Guard clauses

    @Test
    func deliver_givenEmptyUserId_expectFailureAndNoHttpCall() async {
        let (tracker, httpClient) = makeTracker()

        let result: Result<Void, HttpRequestError> = await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "") { result in
                continuation.resume(returning: result)
            }
        }

        #expect(httpClient.requestCallsCount == 0)
        if case .success = result { Issue.record("expected failure for empty userId") }
    }

    @Test
    func deliver_givenNoPersistedApiHost_expectFailureAndNoHttpCall() async {
        let (tracker, httpClient) = makeTracker(contextStore: makeContextStore(host: nil))

        let result: Result<Void, HttpRequestError> = await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "user_42") { result in
                continuation.resume(returning: result)
            }
        }

        #expect(httpClient.requestCallsCount == 0)
        if case .success = result { Issue.record("expected failure for missing apiHost") }
    }

    // MARK: - Result propagation

    @Test
    func deliver_givenHttpFailure_expectFailurePropagated() async {
        let (tracker, httpClient) = makeTracker()
        httpClient.requestClosure = { _, onComplete in
            onComplete(.failure(.unsuccessfulStatusCode(500, apiMessage: "boom")))
        }

        let result: Result<Void, HttpRequestError> = await withCheckedContinuation { continuation in
            tracker.deliver(metric: makeMetric(), userId: "user_42") { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let error) = result {
            if case .unsuccessfulStatusCode(let code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("expected unsuccessfulStatusCode, got \(error)")
            }
        } else {
            Issue.record("expected failure")
        }
    }
}
