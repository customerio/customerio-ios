@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceApiService")
struct GeofenceApiServiceTests {
    private func makeStore(host: String? = "cdp.customer.io/v1", cdpApiKey: String? = "sk_test_abc") -> BackgroundDeliveryContextStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        if let host { store.setApiHost(host) }
        if let cdpApiKey { store.setCdpApiKey(cdpApiKey) }
        return store
    }

    private func makeService(
        store: BackgroundDeliveryContextStore,
        runner: HttpRequestRunnerMock = HttpRequestRunnerMock()
    ) -> (service: GeofenceApiServiceImpl, runner: HttpRequestRunnerMock) {
        let service = GeofenceApiServiceImpl(
            contextStore: store,
            requestRunner: runner,
            session: URLSession(configuration: .ephemeral),
            logger: LoggerMock()
        )
        return (service, runner)
    }

    private func makeOkResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://cdp.customer.io/v1/geofences/nearby")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Request shaping

    @Test
    func fetchGeofences_givenStoreState_expectGetRequestWithQueryAndAuth() async {
        let (service, runner) = makeService(store: makeStore())
        runner.requestClosure = { _, _, onComplete in
            onComplete("{\"geofences\":[]}".data(using: .utf8), makeOkResponse(), nil)
        }

        await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 37.7749, longitude: -122.4194) { _ in continuation.resume() }
        }

        let params = runner.requestReceivedArguments?.params
        #expect(params?.method == "GET")
        #expect(params?.url.absoluteString == "https://cdp.customer.io/v1/geofences/nearby?latitude=37.7749&longitude=-122.4194")
        #expect(params?.headers?["Authorization"] == "Basic c2tfdGVzdF9hYmM6")
        #expect(params?.headers?["Accept"] == "application/json")
        #expect(params?.body == nil)
    }

    @Test
    func fetchGeofences_givenSchemeQualifiedHost_expectSchemeNotDuplicated() async {
        let (service, runner) = makeService(store: makeStore(host: "https://cdp.customer.io/v1"))
        runner.requestClosure = { _, _, onComplete in
            onComplete("{\"geofences\":[]}".data(using: .utf8), makeOkResponse(), nil)
        }

        await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { _ in continuation.resume() }
        }

        let urlString = runner.requestReceivedArguments?.params.url.absoluteString
        #expect(urlString?.hasPrefix("https://cdp.customer.io/v1/geofences/nearby") == true)
        #expect(urlString?.contains("https://https://") == false)
    }

    // MARK: - Guards

    @Test
    func fetchGeofences_givenMissingApiHost_expectMissingApiHostError() async {
        let (service, _) = makeService(store: makeStore(host: nil))

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let err) = result { #expect(err == .missingApiHost) } else { Issue.record("expected failure") }
    }

    @Test
    func fetchGeofences_givenMissingCdpApiKey_expectMissingCdpApiKeyError() async {
        let (service, _) = makeService(store: makeStore(cdpApiKey: nil))

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let err) = result { #expect(err == .missingCdpApiKey) } else { Issue.record("expected failure") }
    }

    // MARK: - Status code mapping

    @Test
    func fetchGeofences_given500_expectHttpError() async {
        let (service, runner) = makeService(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(nil, makeOkResponse(statusCode: 500), nil) }

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(.http(let status)) = result { #expect(status == 500) } else { Issue.record("expected http failure") }
    }

    @Test
    func fetchGeofences_givenTransportError_expectTransportFailure() async {
        let (service, runner) = makeService(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(nil, nil, URLError(.notConnectedToInternet)) }

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let err) = result { #expect(err == .transport) } else { Issue.record("expected transport failure") }
    }

    @Test
    func fetchGeofences_givenMalformedJson_expectDecodingError() async {
        let (service, runner) = makeService(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete("not json".data(using: .utf8), makeOkResponse(), nil) }

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        if case .failure(let err) = result { #expect(err == .decoding) } else { Issue.record("expected decoding failure") }
    }

    // MARK: - Success decoding

    @Test
    func fetchGeofences_givenValidResponse_expectDecodedDomain() async {
        let json = """
        {
          "config": {
            "local_refresh_trigger_radius": 750,
            "remote_fetch_refresh_trigger_radius": 4000,
            "remote_fetch_refresh_expiry_time": 43200000,
            "duplicate_events_expiry_time": 1800000,
            "ios": { "max_business_geofences": 10 }
          },
          "geofences": [
            {
              "id": "g1",
              "name": "Test Region",
              "latitude": 37.7749,
              "longitude": -122.4194,
              "radius": 500,
              "transition_types": ["enter", "exit"],
              "last_updated": 1700000000
            }
          ]
        }
        """
        let (service, runner) = makeService(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(json.data(using: .utf8), makeOkResponse(), nil) }

        let result: Result<GeofenceApiResponse, GeofenceApiError> = await withCheckedContinuation { continuation in
            service.fetchGeofences(latitude: 1.0, longitude: 2.0) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .success(let response) = result else {
            Issue.record("expected success")
            return
        }
        let config = response.toDomainConfig()
        #expect(config?.localRefreshTriggerRadius == 750)
        #expect(config?.remoteFetchRefreshTriggerRadius == 4000)
        #expect(config?.remoteFetchRefreshExpiry == 43200) // ms → s
        #expect(config?.duplicateEventsExpiry == 1800) // ms → s
        #expect(config?.maxBusinessGeofences == 10)

        let regions = response.toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions.first?.id == "g1")
        #expect(regions.first?.name == "Test Region")
        #expect(regions.first?.transitionTypes == [.enter, .exit])
    }
}
