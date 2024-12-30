@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class ScreenViewFilterPluginTests: IntegrationTest {
    var outputReader: OutputReaderPlugin!

    override func setUp() {}

    private func setupWithConfig(screenViewUse: ScreenView, customConfig: ((inout SdkConfig) -> Void)? = nil) {
        super.setUp(modifySdkConfig: { config in
            config.screenViewUse(screenView: screenViewUse)
        })
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    func testProcessGivenScreenViewUseAnalyticsExpectScreenEventWithoutPropertiesProcessed() {
        setupWithConfig(screenViewUse: .all)

        let givenScreenTitle = String.random

        customerIO.screen(title: givenScreenTitle)

        guard let screenEvent = outputReader.screenEvents.first, outputReader.screenEvents.count == 1 else {
            XCTFail("Expected exactly one screen event")
            return
        }

        XCTAssertEqual(screenEvent.name, givenScreenTitle)
        XCTAssertTrue(screenEvent.properties?.dictionaryValue?.isEmpty ?? true)
    }

    func testProcessGivenScreenViewUseAnalyticsExpectScreenEventWithPropertiesProcessed() {
        setupWithConfig(screenViewUse: .all)

        let givenScreenTitle = String.random
        let givenProperties: [String: Any] = [
            "source": "push",
            "discount": 10
        ]

        customerIO.screen(title: givenScreenTitle, properties: givenProperties)

        guard let screenEvent = outputReader.screenEvents.first, outputReader.screenEvents.count == 1 else {
            XCTFail("Expected exactly one screen event")
            return
        }

        XCTAssertEqual(screenEvent.name, givenScreenTitle)
        XCTAssertMatches(
            screenEvent.properties?.dictionaryValue,
            givenProperties,
            withTypeMap: [["discount"]: Int.self]
        )
    }

    func testProcessGivenScreenViewUseInAppExpectAllScreenEventsIgnored() {
        setupWithConfig(screenViewUse: .inApp)

        // Track multiple screen events
        for _ in 1 ... 5 {
            customerIO.screen(title: String.random)
        }

        XCTAssertTrue(outputReader.events.isEmpty)
    }
}
