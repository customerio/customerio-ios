@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOIntegrationTests: IntegrationTest {
    private var queue: Queue {
        diGraph.queue
    }

    private var givenCustomAttributes: [String: Any] {
        CustomAttributesSampleData.givenCustomAttributes
    }

    private var expectedCustomAttributesString: String {
        CustomAttributesSampleData.expectedCustomAttributesString
    }

    // MARK: tests for all public SDK functions that customers can send us custom attributes. Assert that SDK does not modify the passed in custom attributes in anyway including converting JSON keys from camelCase to snake_case, for example.

    func test_identify_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: .random, body: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let requestParams = httpRequestRunnerStub.requestsParams[0]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {\(expectedCustomAttributesString)}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_trackEvent_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.track(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesString)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"event"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_screenEvent_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.screen(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesString)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"screen"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_registerDeviceToken_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for register token
        httpRequestRunnerStub.queueSuccessfulResponse() // for 2nd call to register token with custom attributes
        let givenDeviceToken = String.random

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.registerDeviceToken(givenDeviceToken)
        CustomerIO.shared.deviceAttributes = givenCustomAttributes

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)

        let requestParams = httpRequestRunnerStub.requestsParams[2]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"device":{"attributes":{"app_version":"1.30.887","cio_sdk_version":"2.0.3","device_locale":"en-US","device_manufacturer":"Apple","device_model":"iPhone 14","device_os":"14","firstName":"Dana","HOBBY":"football","last_name":"Green","nested":{"age":20,"is adult":true},"push_enabled":"false"},"id":"\(
            givenDeviceToken
        )","last_used":\(dateUtilStub.nowSeconds),"platform":"iOS"}}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    // MARK: Test backwards compatability from v1 to v2 of SDK as the way JSON data is generated in v2 got changed

    func test_givenExistingQueueTasksv1SDK_expectBeAbleToRunThoseTasksInV2() {
        httpRequestRunnerStub.alwaysReturnSuccessfulResponse()

        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 0)
        sampleDataFilesUtil.saveSdkV1QueueFiles()
        XCTAssertGreaterThan(diGraph.queueStorage.getInventory().count, 0)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertGreaterThan(httpRequestRunnerStub.requestCallsCount, 0)
        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 0)
    }

    // MARK: Testing 400 response from API scenarios

    func test_givenSendTestPushNotification_givenHttp400Response_expectDeleteTaskAndNotRetry() {
        let expectedResponseBodyString = """
        {
            "meta": {
                "errors": [
                    "malformed delivery id: ."
                ]
            }
        }
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        httpRequestRunnerStub.queueResponse(code: 400, data: expectedResponseBodyString.data)

        CustomerIO.shared.trackMetric(deliveryID: "", event: .opened, deviceToken: .random)

        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 1)
        waitForQueueToFinishRunningTasks(queue)
        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    // MARK: Initialization

    func test_initializeSDK_expectAccessSdkConfigFromInstance() {
        XCTAssertNotNil(CustomerIO.shared.siteId) // asserts the SDK has been initiaed.
        XCTAssertNotNil(CustomerIO.shared.config)
    }

    func test_initializeSDK_givenWorkspaceCredentials_expectSdkConfiguredWithCredentials() {
        let givenSiteId = String.random
        let givenApiKey = String.random

        uninitializeSDK()
        CustomerIO.initialize(siteId: givenSiteId, apiKey: givenApiKey, region: .US, configure: nil)

        XCTAssertEqual(CustomerIO.shared.config!.siteId, givenSiteId)
        XCTAssertEqual(CustomerIO.shared.config!.apiKey, givenApiKey)
    }

    // Reproduces edge case where SDK is initialized multiple times in a short amount of time (such as during app launch in a SDK wrapper app).
    // Learn more: https://github.com/customerio/opsbugs/issues/3618
    func test_initializeSdk_givenCallMultipleTimes_expectNoExceptions() {
        // It's very important that this test runs using real background threads to make SDK initialization async.

        diGraph.resetOverride(forType: ThreadUtil.self)
        let threadRunCountBeforeTest = threadUtilStub.runCount // test class may have already initialized the SDK once. Get count now to see if it's modified after test.

        // 1000 is arbitrary. From running, exception is thrown consistently between index 100 and index 500.
        for _ in 0 ..< 1000 {
            CustomerIO.initialize(siteId: .random, apiKey: .random, region: .US, configure: nil)
        }

        // Assert that test executed using real background threads.
        XCTAssertEqual(threadUtilStub.runCount, threadRunCountBeforeTest)
    }

    // The SDK initialization involves async operations. Assert that the async operations all exectute and do not get skipped with multiple requests.
    func test_initializeSdk_givenCallMultipleTimes_expectFinishAsyncInitialize() {
        let givenNumberOfInitCalls = 500
        let expectCleanupMultipleTimes = expectation(description: "cleanup multiple times")
        expectCleanupMultipleTimes.expectedFulfillmentCount = givenNumberOfInitCalls

        // The cleanup repository is the async operation that executes during SDK initialization.
        // Assert that cleanup executes as many times as the SDK is initialized.
        let cleanupRepositoryMock = CleanupRepositoryMock()
        cleanupRepositoryMock.cleanupClosure = {
            Thread.sleep(forTimeInterval: 0.1) // sleep for 100 milliseconds to simulate async operation
            expectCleanupMultipleTimes.fulfill()
        }

        diGraph.resetOverride(forType: ThreadUtil.self) // use real background threads to assert we are running async operations.
        diGraph.override(value: cleanupRepositoryMock, forType: CleanupRepository.self)

        for _ in 0 ..< givenNumberOfInitCalls {
            CustomerIO.initializeIntegrationTests(diGraph: diGraph)
        }

        waitForExpectations(timeout: 3)
    }
}
