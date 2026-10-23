@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
import Foundation
@testable import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

class HttpClientTest: UnitTest {
    private var requestRunnerMock = HttpRequestRunnerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let timerMock = SimpleTimerMock()

    private var client: RichPushHttpClient!

    private let url = URL(string: "https://customer.io")!

    override func setUp(
        enableLogs: Bool = false,
        modifyModuleConfig: ((MessagingPushConfigBuilder) -> Void)? = nil
    ) {
        super.setUp(enableLogs: enableLogs, modifyModuleConfig: modifyModuleConfig)

        mockCollection.add(mocks: [requestRunnerMock, globalDataStoreMock, timerMock])

        client = RichPushHttpClient(
            jsonAdapter: jsonAdapter,
            httpRequestRunner: requestRunnerMock,
            logger: log,
            userAgentUtil: diGraphShared.userAgentUtil
        )
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: DeviceInfoStub(), forType: DeviceInfo.self)
    }

    // MARK: request

    func test_request_givenErrorDuringRequest_expectError() {
        let givenError = URLError(.notConnectedToInternet)

        mockRequestResponse {
            (body: nil, response: nil, failure: givenError)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noOrBadNetwork(let actualError) = result.error!,
                  case .notConnectedToInternet = actualError.code
            else {
                return XCTFail("expect request failed because not connected to internet")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoResponse_expectError() {
        mockRequestResponse {
            (body: "".data, response: nil, failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else {
                return XCTFail("expect no request was made")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoData_expectError() {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else {
                return XCTFail("expect no request was made")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    func test_request_givenEuRegion_expectRequestToBeMade() {
        super.setUp(modifyModuleConfig: { config in
            config.region(Region.EU)
        })

        let expected = #"{ "message": "Success!" }"#.data!

        mockRequestResponse {
            (body: expected, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: messagingPushConfigOptions.region),
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)

            XCTAssertNil(result.error)

            XCTAssertEqual(result.success, expected)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenSuccessfulResponse_expectGetResponseBody() {
        let expected = #"{ "message": "Success!" }"#.data!

        mockRequestResponse {
            (body: expected, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: messagingPushConfigOptions.region),
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNil(result.error)

            XCTAssertEqual(result.success, expected)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    // MARK: getBasicAuthHeaderString

    func test_getBasicAuthHeaderString_givenHardCodedCredentials_expectCorrectString() {
        let givenCdpApiKey = "oofjwo88283899c9jend"
        let expected = "b29mandvODgyODM4OTljOWplbmQ6"
        let actual = RichPushHttpClient.authorizationHeaderForCdpApiKey(givenCdpApiKey)
        XCTAssertEqual(actual, expected)
    }

    // MARK: getCIOsessionHeader

    func test_getCIOsessionHeader_givenSecretKey_expectNoAuthorizationHeader() {
        let headers = RichPushHttpClient.getCIOsessionHeader(cdpApiKey: "sk_us_\(String.random)", userAgentHeaderValue: "ua")

        XCTAssertNil(headers["Authorization"])
    }

    func test_getCIOsessionHeader_givenPublicOrLegacyKey_expectAuthorizationHeader() {
        let givenPublicKey = "pk_us_\(String.random)"
        let givenLegacyKey = String.random

        XCTAssertEqual(
            RichPushHttpClient.getCIOsessionHeader(cdpApiKey: givenPublicKey, userAgentHeaderValue: "ua")["Authorization"],
            "Basic \(RichPushHttpClient.authorizationHeaderForCdpApiKey(givenPublicKey))"
        )
        XCTAssertEqual(
            RichPushHttpClient.getCIOsessionHeader(cdpApiKey: givenLegacyKey, userAgentHeaderValue: "ua")["Authorization"],
            "Basic \(RichPushHttpClient.authorizationHeaderForCdpApiKey(givenLegacyKey))"
        )
    }

    // MARK: getSessionForRequest

    func test_getSessionForRequest_givenCIOApiEndpoint_expectGetCIOApiSession() {
        let cioApiEndpointUrl = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!.url

        let actualSession = client.getSessionForRequest(url: cioApiEndpointUrl)

        let containsAuthorizationHeader = actualSession.configuration.httpAdditionalHeaders!["Authorization"] != nil
        XCTAssertTrue(containsAuthorizationHeader)
    }

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    func test_getSessionForRequest_givenCIOEUApiEndpoint_expectGetCIOApiSession() {
        setUp(modifyModuleConfig: { config in
            config.region(.EU)
        })
        let cioApiEndpointUrl = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.EU),
            headers: nil,
            body: nil
        )!.url

        let actualSession = client.getSessionForRequest(url: cioApiEndpointUrl)

        let containsAuthorizationHeader = actualSession.configuration.httpAdditionalHeaders!["Authorization"] != nil
        XCTAssertTrue(containsAuthorizationHeader)
    }

    func test_getDefaultApiHost_givenRegion_expectCorrectApiHost() {
        XCTAssertEqual(RichPushHttpClient.getDefaultApiHost(region: .US), "https://cdp.customer.io/v1")
        XCTAssertEqual(RichPushHttpClient.getDefaultApiHost(region: .EU), "https://cdp-eu.customer.io/v1")
    }

    func test_getSessionForRequest_givenCIOAssetLibraryEndpoint_expectPublicSession() {
        let actualSession = client.getSessionForRequest(url: URL(string: "https://storage.googleapis.com/cio-asset-manager-standalone/1670599791846_frederick_adoption_day.jpg")!)

        let containsAuthorizationHeader = actualSession.configuration.httpAdditionalHeaders?["Authorization"] != nil
        XCTAssertFalse(containsAuthorizationHeader)
    }

    // MARK: custom apiHost

    func test_getApiHost_givenNoApiHost_expectRegionDefaultHost() {
        XCTAssertEqual(RichPushHttpClient.getApiHost(config: .withApiHost(nil)), "https://cdp.customer.io/v1")
        XCTAssertEqual(RichPushHttpClient.getApiHost(config: .withApiHost(nil, region: .EU)), "https://cdp-eu.customer.io/v1")
    }

    func test_getApiHost_givenEmptyApiHost_expectRegionDefaultHost() {
        XCTAssertEqual(RichPushHttpClient.getApiHost(config: .withApiHost("")), "https://cdp.customer.io/v1")
    }

    func test_getApiHost_givenApiHostWithoutScheme_expectHttpsPrepended() {
        XCTAssertEqual(RichPushHttpClient.getApiHost(config: .withApiHost("proxy.example.com/v1")), "https://proxy.example.com/v1")
    }

    func test_getApiHost_givenApiHostWithScheme_expectSchemeKept() {
        XCTAssertEqual(RichPushHttpClient.getApiHost(config: .withApiHost("http://localhost:8080/v1")), "http://localhost:8080/v1")
    }

    func test_getSessionForRequest_givenCustomApiHost_expectCIOApiSessionForCustomHost() {
        setUpClient(moduleConfig: .withApiHost("proxy.example.com/v1"))

        let actualSession = client.getSessionForRequest(url: URL(string: "https://proxy.example.com/v1/track")!)

        XCTAssertNotNil(actualSession.configuration.httpAdditionalHeaders?["Authorization"])
    }

    func test_getSessionForRequest_givenCustomApiHost_expectPublicSessionForDefaultHost() {
        setUpClient(moduleConfig: .withApiHost("proxy.example.com/v1"))

        let actualSession = client.getSessionForRequest(url: URL(string: "https://cdp.customer.io/v1/track")!)

        XCTAssertNil(actualSession.configuration.httpAdditionalHeaders?["Authorization"])
    }

    func test_getSessionForRequest_givenInvalidApiHost_expectPublicSession() {
        setUpClient(moduleConfig: .withApiHost("proxy example.com/v1"))

        let actualSession = client.getSessionForRequest(url: URL(string: "https://cdp.customer.io/v1/track")!)

        XCTAssertNil(actualSession.configuration.httpAdditionalHeaders?["Authorization"])
    }
}

extension HttpClientTest {
    // The client reads the module config when it's created, so recreate it after changing the config.
    private func setUpClient(moduleConfig: MessagingPushConfigOptions) {
        setUp(moduleConfig: moduleConfig)
        client = RichPushHttpClient(
            jsonAdapter: jsonAdapter,
            httpRequestRunner: requestRunnerMock,
            logger: log,
            userAgentUtil: diGraphShared.userAgentUtil
        )
    }

    // OK with a large tuple since this is just setting up a test. No need to make a custom data type just to setup test functions.
    // swiftlint:disable:next large_tuple
    private func mockRequestResponse(onComplete: @escaping () -> (body: Data?, response: HTTPURLResponse?, failure: Error?)) {
        requestRunnerMock.requestClosure = { _, _, actualOnComplete in
            let result = onComplete()
            actualOnComplete(result.body, result.response, result.failure)
        }
    }
}
