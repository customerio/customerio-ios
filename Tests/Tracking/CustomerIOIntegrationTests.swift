@testable import CioTracking
@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class CustomerIOIntegrationTests: IntegrationTest {
    private var queue: Queue {
        diGraph.queue
    }
    private var implementation: CustomerIOImplementation!
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `CustomerIOImplementation`.
    private var customerIO: CustomerIO!
    
    private var sdkConfig : SdkConfigStore {
        diGraph.sdkConfigStore
    }

    private var givenCustomAttributes: [String: Any] {
        CustomAttributesSampleData.givenCustomAttributes
    }

    private var expectedCustomAttributesStringSnakeCasingDisabled: String {
        CustomAttributesSampleData.expectedCustomAttributesString
    }
    
    private var expectedCustomAttributesStringSnakeCasingEnabled : String {
        CustomAttributesSampleData.expectedCustomAttributesStringSnakeCasingEnabled
    }

    override func setUp() {
        super.setUp()
        
        implementation = CustomerIOImplementation(siteId: diGraph.siteId)
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)
        
        configureSDK()
    }
    
    private func configureSDK(enableSnakeCasing: Bool = false) {
        customerIO.config {
            $0.disableCustomAttributeSnakeCasing = !enableSnakeCasing
        }
    }
    
    // MARK: tests for all public SDK functions that customers can send us custom attributes. Assert that SDK does not modify the passed in custom attributes in anyway including converting JSON keys from camelCase to snake_case, for example.

    // Expectations - Do not modify
    func test_identify_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: .random, body: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let requestParams = httpRequestRunnerStub.requestsParams[0]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {\(expectedCustomAttributesStringSnakeCasingDisabled)}
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
        {"data":{\(expectedCustomAttributesStringSnakeCasingDisabled)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"event"}
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
        {"data":{\(expectedCustomAttributesStringSnakeCasingDisabled)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"screen"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
    
    // Expectation - Modified Custom Attributes
    
    func test_identify_givenCustomAttributes_expectModifiedCustomAttributes() {
        configureSDK(enableSnakeCasing: true)
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: .random, body: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let requestParams = httpRequestRunnerStub.requestsParams[0]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {\(expectedCustomAttributesStringSnakeCasingEnabled)}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
    
    
    func test_trackEvent_givenCustomAttributes_expectModifiedCustomAttributes() {
        configureSDK(enableSnakeCasing: true)
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.track(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesStringSnakeCasingEnabled)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"event"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
    
    func test_screenEvent_givenCustomAttributes_expectModifiedCustomAttributes() {
        configureSDK(enableSnakeCasing: true)
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.screen(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesStringSnakeCasingEnabled)},"name":"foo","timestamp":\(dateUtilStub.nowSeconds),"type":"screen"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
}
