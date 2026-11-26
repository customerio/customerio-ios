@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import UIKit
import XCTest

/// Automatic screen views reach Segment through the gateway the factory built, like every other call, so a
/// stand-in set through the factory sees them.
class AutoScreenGatewayTests: IntegrationTest {
    private var recordingGateway: RecordingScreenGateway!

    override func setUpDependencies() {
        super.setUpDependencies()

        let recording = RecordingScreenGateway()
        recordingGateway = recording
        diGraphShared.override(
            value: SegmentFactory(
                makeAnalytics: SegmentFactory.live.makeAnalytics,
                makeGateway: { analytics in
                    recording.wrapped = AnalyticsSegmentGateway(analytics: analytics)
                    return recording
                }
            ),
            forType: SegmentFactory.self
        )
    }

    func test_performScreenTracking_givenFactoryOverride_expectScreenHandedToFactoryGateway() {
        class ViewInsideOfHostApp: UIViewController {}
        let plugin = CustomerIO.shared.add(plugin: AutoTrackingScreenViews()) as! AutoTrackingScreenViews // swiftlint:disable:this force_cast

        plugin.performScreenTracking(onViewController: ViewInsideOfHostApp())

        XCTAssertEqual(recordingGateway.screenTitles.count, 1)
    }
}

/// Records screens and passes every call to a live gateway.
private final class RecordingScreenGateway: SegmentGateway {
    var wrapped: SegmentGateway!
    private(set) var screenTitles: [String] = []

    var userId: String? { wrapped.userId }
    var anonymousId: String { wrapped.anonymousId }

    func identify(userId: String, traits: [String: Any]?) {
        wrapped.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(userId: String, traits: T?) {
        wrapped.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(traits: T) {
        wrapped.identify(traits: traits)
    }

    func track(name: String) {
        wrapped.track(name: name)
    }

    func track(name: String, properties: [String: Any]?) {
        wrapped.track(name: name, properties: properties)
    }

    func track<P: Codable>(name: String, properties: P?) {
        wrapped.track(name: name, properties: properties)
    }

    func track(name: String, properties: [String: Any]?, deviceToken: String) {
        wrapped.track(name: name, properties: properties, deviceToken: deviceToken)
    }

    func screen(title: String, category: String?) {
        screenTitles.append(title)
        wrapped.screen(title: title, category: category)
    }

    func screen(title: String, category: String?, properties: [String: Any]?) {
        screenTitles.append(title)
        wrapped.screen(title: title, category: category, properties: properties)
    }

    func screen<P: Codable>(title: String, category: String?, properties: P?) {
        screenTitles.append(title)
        wrapped.screen(title: title, category: category, properties: properties)
    }

    func alias(newId: String) {
        wrapped.alias(newId: newId)
    }

    func reset() {
        wrapped.reset()
    }

    func process(event: RawEvent) {
        wrapped.process(event: event)
    }
}
