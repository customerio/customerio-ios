@testable import CioTracking
@testable import Common
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

    // MARK: Background queue behavior

    // Adding of tasks to the SDK's background queue is performed on an OS background thread using an OS provided queue data structure. It's possible to configure the OS to run these background threads concurrently instead of serially which would add tasks to the background queue in a random order. This could cause HTTP errors as our background queue expects all tasks are in a specific order of events.
    // This test sends lots of requests to the SDK and then we verify that all tasks added to the background queue are in order.
    func test_backgroundQueue_givenAddManyRequestsToSDK_expectAddAllRequestsToBackgroundQueueInOrder() {
        let numberOfTasksToAdd = 500

        setUp { config in
            // disable the background queue from executing so we don't need to stub HTTP requests in this test. This test is just testing adding tasks to the queue, not executing tasks in the queue.
            config.backgroundQueueMinNumberOfTasks = numberOfTasksToAdd + 1
        }

        for index in 0 ..< numberOfTasksToAdd {
            // Using trackMetric since it does not have requirements such as a profile identified to the SDK.
            // Use loop index for the data to make it easy to verify queue tasks added in order.
            CustomerIO.shared.trackMetric(deliveryID: String(index), event: .opened, deviceToken: String(index))
        }

        // Loop to wait for SDK to finish asynchronously adding tasks to the background queue.
        while true {
            let numberOfTasksAddedThusFar = diGraph.queueStorage.getInventory().count

            if numberOfTasksToAdd == numberOfTasksAddedThusFar {
                break
            }
        }

        XCTAssertEqual(diGraph.queueStorage.getInventory().count, numberOfTasksToAdd)

        for (index, queueTaskMetadata) in diGraph.queueStorage.getInventory().enumerated() {
            let queueTask = diGraph.queueStorage.get(storageId: queueTaskMetadata.taskPersistedId)!
            let queueTaskData: MetricRequest = jsonAdapter.fromJson(queueTask.data)!

            // This will fail our test if a task was added into the background queue out of order.
            // We expect the inventory to have tasks: [1, 2, 3...] based on a loop index.
            XCTAssertEqual(String(index), queueTaskData.deliveryId)
        }

        // Assert that test function executed using production threading code in the SDK and not mocked.
        XCTAssertFalse(threadUtilStub.mockCalled)
    }
}
