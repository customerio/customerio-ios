@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class DataPipelineMigrationTests: IntegrationTest {
    private var dataPipelineImplementation: DataPipelineImplementation!

    override func setUpDependencies() {
        super.setUpDependencies()
    }

    override func setUp() {
        super.setUp(modifySdkConfig: { _ in
        })

        // get DataPipelineImplementation instance so we can call its methods directly
        dataPipelineImplementation = (customerIO.implementation as! DataPipelineImplementation) // swiftlint:disable:this force_cast
    }

    func test_givenUserAlreadyIdentified_expectIdentifyUser() {
        let givenIdentifer = String.random
        XCTAssertNotNil(dataPipelineImplementation.processAlreadyIdentifiedUser(identifier: givenIdentifer))
        XCTAssertEqual(analytics.userId, givenIdentifer)
    }

    func test_givenProfileIdentifiedFromBGQ_expectProcessEvent() {
        let givenIdentifer = String.random
        let timestamp = dateUtilStub.now.toString()
        let body = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processIdentifyFromBGQ(identifier: givenIdentifer, timestamp: timestamp, body: body))
    }

    func test_givenScreenEventFromBGQ_expectProcessEvent() {
        let givenIdentifer = String.random
        let screenName = String.random
        let timestamp = dateUtilStub.now.toString()
        let body = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processScreenEventFromBGQ(identifier: givenIdentifer, name: screenName, timestamp: timestamp, properties: body))
    }

    func test_givenEventFromBGQ_expectProcessEvent() {
        let givenIdentifer = String.random
        let eventName = String.random
        let timestamp = dateUtilStub.now.toString()
        let body = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processEventFromBGQ(identifier: givenIdentifer, name: eventName, timestamp: timestamp, properties: body))
    }

    func test_givenDeleteTokenFromBGQ_expectProcessEvent() {
        let givenIdentifer = String.random
        let token = String.random
        let timestamp = dateUtilStub.now.toString()
        XCTAssertNotNil(dataPipelineImplementation.processDeleteTokenFromBGQ(identifier: givenIdentifer, token: token, timestamp: timestamp))
    }

    func test_givenRegisterDeviceTokenFromBGQ_expectProcessEvent() {
        let givenIdentifer = String.random
        let token = String.random
        let timestamp = dateUtilStub.now.toString()
        let body = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processRegisterDeviceFromBGQ(identifier: givenIdentifer, token: token, timestamp: timestamp, attributes: body))
    }

    func test_givenInAppMetricsFromBGQ_expectProcessEvent() {
        let deliveryId = String.random
        let timestamp = dateUtilStub.now.toString()
        let metaData = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processMetricsFromBGQ(token: nil, event: "opened", deliveryId: deliveryId, timestamp: timestamp, metaData: metaData))
    }

    func test_givenPushMetricsFromBGQ_expectProcessEvent() {
        let token = String.random
        let deliveryId = String.random
        let timestamp = dateUtilStub.now.toString()
        let metaData = ["foo": "bar"]
        XCTAssertNotNil(dataPipelineImplementation.processMetricsFromBGQ(token: token, event: "opened", deliveryId: deliveryId, timestamp: timestamp, metaData: metaData))
    }
}
