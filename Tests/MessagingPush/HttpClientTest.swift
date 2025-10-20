@testable import CioInternalCommon
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

    func test_request_givenErrorDuringRequest_expectError() async {
        let givenError = URLError(.notConnectedToInternet)

        mockRequestResponse {
            (body: nil, response: nil, failure: givenError)
        }

        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        let result = await client.request(params)
        
        XCTAssertTrue(self.requestRunnerMock.requestCalled)
        guard case .noOrBadNetwork(let actualError) = result.error!,
              case .notConnectedToInternet = actualError.code
        else {
            return XCTFail("expect request failed because not connected to internet")
        }
    }

    func test_request_givenNoResponse_expectError() async {
        mockRequestResponse {
            (body: "".data, response: nil, failure: nil)
        }

        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        let result = await client.request(params)
        
        XCTAssertTrue(self.requestRunnerMock.requestCalled)
        guard case .noRequestMade = result.error! else {
            return XCTFail("expect no request was made")
        }
    }

    func test_request_givenNoData_expectError() async {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: Region.US),
            headers: nil,
            body: nil
        )!
        let result = await client.request(params)
        
        XCTAssertTrue(self.requestRunnerMock.requestCalled)
        guard case .noRequestMade = result.error! else {
            return XCTFail("expect no request was made")
        }
    }

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    func test_request_givenEuRegion_expectRequestToBeMade() async {
        super.setUp(modifyModuleConfig: { config in
            config.region(Region.EU)
        })

        let expected = #"{ "message": "Success!" }"#.data!

        mockRequestResponse {
            (body: expected, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: messagingPushConfigOptions.region),
            headers: nil,
            body: nil
        )!
        let result = await client.request(params)
        
        XCTAssertTrue(self.requestRunnerMock.requestCalled)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.success, expected)
    }

    func test_request_givenSuccessfulResponse_expectGetResponseBody() async {
        let expected = #"{ "message": "Success!" }"#.data!

        mockRequestResponse {
            (body: expected, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: messagingPushConfigOptions.region),
            headers: nil,
            body: nil
        )!
        let result = await client.request(params)
        
        XCTAssertTrue(self.requestRunnerMock.requestCalled)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.success, expected)
    }

    // MARK: getBasicAuthHeaderString

    func test_getBasicAuthHeaderString_givenHardCodedCredentials_expectCorrectString() {
        let givenCdpApiKey = "oofjwo88283899c9jend"
        let expected = "b29mandvODgyODM4OTljOWplbmQ6"
        let actual = RichPushHttpClient.authorizationHeaderForCdpApiKey(givenCdpApiKey)
        XCTAssertEqual(actual, expected)
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
}

extension HttpClientTest {
    // OK with a large tuple since this is just setting up a test. No need to make a custom data type just to setup test functions.
    // swiftlint:disable:next large_tuple
    private func mockRequestResponse(onComplete: @escaping () -> (body: Data?, response: HTTPURLResponse?, failure: Error?)) {
        requestRunnerMock.requestClosure = { _, _ in
            let result = onComplete()
            if let failure = result.failure {
                throw failure
            }
            guard let body = result.body, let response = result.response else {
                throw URLError(.badServerResponse)
            }
            return (body, response)
        }
    }
}
