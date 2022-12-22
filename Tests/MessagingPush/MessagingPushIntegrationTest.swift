@testable import CioTracking
@testable import Common
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushIntegrationTests: IntegrationTest {
    private var queue: Queue {
        diGraph.queue
    }
    
    private var sdkConfig: SdkConfigStore {
        diGraph.sdkConfigStore
    }
    
    private var givenCustomAttributes: [String: Any] {
        CustomAttributesSampleData.givenCustomAttributes
    }
    private var expectedSnakeCaseModifiedString: String {
        CustomAttributesSampleData.expectedSnakeCaseModifiedString
    }
    private var expectedNotModifiedString: String {
        CustomAttributesSampleData.expectedNotModifiedString
    }
    
    private func configureSDK(enableSnakeCaseBugFix: Bool) {
        CustomerIO.config {
            $0.disableCustomAttributeSnakeCasing = enableSnakeCaseBugFix
        }
    }
    
    override func setUp() {
        super.setUp()
        
        _ = MessagingPush(customerIO: CustomerIO.shared) // must do this to start module hooks so Http requests to register device tokens will work
    }
    
    // MARK: tests for all public SDK functions that customers can send us custom attributes. Assert that SDK does not modify the passed in custom attributes in anyway including converting JSON keys from camelCase to snake_case, for example.
    
    // MARK: disable snake_case bug fix - expect to modify custom attributes keys to snake_case
    
    func test_registerDeviceToken_givenDisableSnakecaseBugFix_expectModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for register token
        httpRequestRunnerStub.queueSuccessfulResponse() // for 2nd call to register token with custom attributes
        let givenDeviceToken = String.random
        
        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        MessagingPush.shared.registerDeviceToken(givenDeviceToken)
        CustomerIO.shared.deviceAttributes = givenCustomAttributes
        
        waitForQueueToFinishRunningTasks(queue)
        
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
        
        let requestParams = httpRequestRunnerStub.requestsParams[2]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"device":{"attributes":{"app_version":"1.30.887","cio_sdk_version":"2.0.3","device_locale":"en-US","device_manufacturer":"Apple","device_model":"iPhone 14","device_os":"14",\(expectedSnakeCaseModifiedString),"push_enabled":"false"},"id":"\(
            givenDeviceToken
        )","last_used":\(dateUtilStub.nowSeconds),"platform":"iOS"}}
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
    
    // MARK: enable snake_case bug fix - expect to *not* modify custom attributes keys
    
    func test_registerDeviceToken_givenEnableSnakecaseBugFix_expectDoNotModifyCustomAttributes() {
        configureSDK(enableSnakeCaseBugFix: true)
        
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for register token
        httpRequestRunnerStub.queueSuccessfulResponse() // for 2nd call to register token with custom attributes
        let givenDeviceToken = String.random
        
        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        MessagingPush.shared.registerDeviceToken(givenDeviceToken)
        CustomerIO.shared.deviceAttributes = givenCustomAttributes
        
        waitForQueueToFinishRunningTasks(queue)
        
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
        
        let requestParams = httpRequestRunnerStub.requestsParams[2]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"device":{"attributes":{"app_version":"1.30.887","cio_sdk_version":"2.0.3","device_locale":"en-US","device_manufacturer":"Apple","device_model":"iPhone 14","device_os":"14",\(expectedNotModifiedString),"push_enabled":"false"},"id":"\(
            givenDeviceToken
        )","last_used":\(dateUtilStub.nowSeconds),"platform":"iOS"}}
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
    

    // MARK: Test backwards compatability from v1 to v2 of SDK as the way JSON data is generated in v2 got changed
    func test_givenExistingQueueTasksv1SDK_expectBeAbleToRunThoseTasksInV2() {
        httpRequestRunnerStub.alwaysReturnSuccessfulResponse()
        
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 0)
        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 0)
        sampleDataFilesUtil.saveSdkV1QueueFiles()
        XCTAssertGreaterThan(diGraph.queueStorage.getInventory().count, 0)
        
        waitForQueueToFinishRunningTasks(queue)
        
        XCTAssertGreaterThan(httpRequestRunnerStub.requestCallsCount, 0)
        XCTAssertEqual(diGraph.queueStorage.getInventory().count, 0)
    }
}
