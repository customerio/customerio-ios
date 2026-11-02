@testable import CioMessagingPush
import XCTest

final class BackgroundPushReadinessTest: XCTestCase {
    func test_readinessRequiresHostOptInAndTheActualBackgroundMode() {
        XCTAssertTrue(BackgroundPushReadiness.isReady(enabled: true, backgroundModes: ["fetch", "remote-notification"]))
        for modes: Any? in [nil, "remote-notification", ["fetch"], [] as [String]] {
            XCTAssertFalse(BackgroundPushReadiness.isReady(enabled: true, backgroundModes: modes))
        }
        XCTAssertFalse(BackgroundPushReadiness.isReady(enabled: false, backgroundModes: ["remote-notification"]))
    }
}
