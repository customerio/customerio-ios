@testable import CioInternalCommon
import Foundation
import SharedTests
import Testing

@Suite("BackgroundDeliveryHttpClient")
struct BackgroundDeliveryHttpClientTests {
    private func makeStore(host: String? = "cdp.customer.io/v1", cdpApiKey: String? = "sk_test_abc") -> BackgroundDeliveryContextStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        if let host { store.setApiHost(host) }
        if let cdpApiKey { store.setCdpApiKey(cdpApiKey) }
        return store
    }

    private func makeClient(
        store: BackgroundDeliveryContextStore,
        runner: HttpRequestRunnerMock = HttpRequestRunnerMock()
    ) -> (client: BackgroundDeliveryHttpClientImpl, runner: HttpRequestRunnerMock) {
        let client = BackgroundDeliveryHttpClientImpl(
            contextStore: store,
            requestRunner: runner,
            session: URLSession(configuration: .ephemeral),
            logger: LoggerMock()
        )
        return (client, runner)
    }

    private func makeOkResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://cdp.customer.io/v1/track")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Wire format

    @Test
    func sendTrackEvent_givenStoreState_expectRequestUrlAndAuthAndBody() async {
        let (client, runner) = makeClient(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(Data(), makeOkResponse(), nil) }

        await withCheckedContinuation { continuation in
            client.sendTrackEvent(
                eventName: "GeoFence Entered",
                userId: "user_42",
                properties: ["geofence_id": "geo_1", "transition_type": "enter"]
            ) { _ in continuation.resume() }
        }

        let params = runner.requestReceivedArguments?.params
        #expect(params?.url.absoluteString == "https://cdp.customer.io/v1/track")
        #expect(params?.method == "POST")
        #expect(params?.headers?["Authorization"] == "Basic c2tfdGVzdF9hYmM6")
        #expect(params?.headers?["Content-Type"] == "application/json; charset=utf-8")

        let body = params?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(body?["event"] as? String == "GeoFence Entered")
        #expect(body?["userId"] as? String == "user_42")
        let properties = body?["properties"] as? [String: Any]
        #expect(properties?["geofence_id"] as? String == "geo_1")
        #expect(properties?["transition_type"] as? String == "enter")
    }

    @Test
    func sendTrackEvent_givenSchemeQualifiedHost_expectSchemeNotDuplicated() async {
        let (client, runner) = makeClient(store: makeStore(host: "https://cdp-eu.customer.io/v1"))
        runner.requestClosure = { _, _, onComplete in onComplete(Data(), makeOkResponse(), nil) }

        await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { _ in
                continuation.resume()
            }
        }

        #expect(runner.requestReceivedArguments?.params.url.absoluteString == "https://cdp-eu.customer.io/v1/track")
    }

    // MARK: - Guard clauses

    @Test
    func sendTrackEvent_givenMissingApiHost_expectMissingApiHostError() async {
        let (client, runner) = makeClient(store: makeStore(host: nil))

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { continuation.resume(returning: $0) }
        }

        #expect(runner.requestCallsCount == 0)
        if case .failure(let error) = result {
            #expect(error == .missingApiHost)
        } else {
            Issue.record("expected failure")
        }
    }

    @Test
    func sendTrackEvent_givenMissingCdpApiKey_expectMissingCdpApiKeyError() async {
        let (client, runner) = makeClient(store: makeStore(cdpApiKey: nil))

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { continuation.resume(returning: $0) }
        }

        #expect(runner.requestCallsCount == 0)
        if case .failure(let error) = result {
            #expect(error == .missingCdpApiKey)
        } else {
            Issue.record("expected failure")
        }
    }

    // MARK: - Status mapping

    @Test
    func sendTrackEvent_given500_expectHttpFailure() async {
        let (client, runner) = makeClient(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(nil, makeOkResponse(statusCode: 500), nil) }

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { continuation.resume(returning: $0) }
        }

        if case .failure(let error) = result {
            #expect(error == .http(statusCode: 500))
        } else {
            Issue.record("expected failure")
        }
    }

    @Test
    func sendTrackEvent_given204_expectSuccess() async {
        let (client, runner) = makeClient(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(nil, makeOkResponse(statusCode: 204), nil) }

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { continuation.resume(returning: $0) }
        }

        if case .failure = result { Issue.record("expected success for 204") }
    }

    @Test
    func sendTrackEvent_givenTransportError_expectTransportFailure() async {
        let (client, runner) = makeClient(store: makeStore())
        runner.requestClosure = { _, _, onComplete in onComplete(nil, nil, URLError(.notConnectedToInternet)) }

        let result: Result<Void, BackgroundDeliveryHttpError> = await withCheckedContinuation { continuation in
            client.sendTrackEvent(eventName: "event", userId: "user", properties: [:]) { continuation.resume(returning: $0) }
        }

        if case .failure(let error) = result {
            #expect(error == .transport)
        } else {
            Issue.record("expected failure")
        }
    }
}
