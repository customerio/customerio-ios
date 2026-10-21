@testable import CioAnalytics
@testable import CioDataPipelines
import Foundation
import SharedTests
import UIKit
import XCTest

class MissedLaunchLifecycleReplayTest: UnitTest {
    private var notificationCenter: NotificationCenter!
    private var callbacksRecorder: LifecycleCallbacksRecorder!
    private var scheduledOnMainQueue: [() -> Void] = []

    override func setUp() {
        super.setUp()

        notificationCenter = NotificationCenter()
        callbacksRecorder = LifecycleCallbacksRecorder()
        analytics.add(plugin: callbacksRecorder)
    }

    private func createSubject(state: UIApplication.State?) -> MissedLaunchLifecycleReplay {
        MissedLaunchLifecycleReplay(
            analytics: analytics,
            notificationCenter: notificationCenter,
            applicationState: { state },
            runOnMainQueue: { [weak self] block in self?.scheduledOnMainQueue.append(block) }
        )
    }

    private func runScheduledOnMainQueue() {
        let blocks = scheduledOnMainQueue
        scheduledOnMainQueue.removeAll()
        blocks.forEach { $0() }
    }

    private func startOnBackgroundThread(_ subject: MissedLaunchLifecycleReplay) {
        let returned = expectation(description: "start() returned on a background thread")
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            subject.start()
            returned.fulfill()
        }
        wait(for: [returned], timeout: 1)
    }

    // MARK: - App already active

    func test_start_whenAppActive_thenReplaysLaunchAndBecomeActiveImmediately() {
        let subject = createSubject(state: .active)

        subject.start()

        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching, .didBecomeActive])
        XCTAssertTrue(scheduledOnMainQueue.isEmpty)
    }

    func test_start_whenAppActive_thenTracksInstalledAndFirstOpenedAndForegrounded() {
        UserDefaults.standard.removeObject(forKey: "SEGVersionKey")
        UserDefaults.standard.removeObject(forKey: "SEGBuildKeyV2")
        let outputReader = OutputReaderPlugin()
        analytics.add(plugin: outputReader)
        let subject = createSubject(state: .active)

        subject.start()

        let lifecycleEvents = outputReader.events
            .compactMap { $0 as? TrackEvent }
            .filter { $0.event.hasPrefix("Application ") }
        XCTAssertEqual(
            lifecycleEvents.map(\.event),
            ["Application Installed", "Application Opened", "Application Foregrounded"]
        )
        XCTAssertEqual(lifecycleEvents[1].properties?.dictionaryValue?["from_background"] as? Bool, false)
    }

    // MARK: - App inactive or in background

    func test_start_whenAppInactiveAndLaunchNotificationArrives_thenReplaysNothing() {
        let subject = createSubject(state: .inactive)

        subject.start()
        notificationCenter.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [])
    }

    func test_start_whenAppInactiveAndLaunchAlreadyHappened_thenReplaysLaunchOnNextMainQueueRun() {
        let subject = createSubject(state: .inactive)

        subject.start()
        XCTAssertEqual(callbacksRecorder.callbacks, [])

        runScheduledOnMainQueue()
        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching])
    }

    func test_start_whenAppInBackgroundAndLaunchNotificationArrives_thenReplaysNothing() {
        let subject = createSubject(state: .background)

        subject.start()
        notificationCenter.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [])
    }

    func test_start_whenAppInBackgroundAndLaunchAlreadyHappened_thenReplaysLaunchOnNextMainQueueRun() {
        let subject = createSubject(state: .background)

        subject.start()
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching])
    }

    func test_start_whenLaunchNotificationArrivesAfterCheck_thenReplaysOnlyOnce() {
        let subject = createSubject(state: .inactive)

        subject.start()
        runScheduledOnMainQueue()
        notificationCenter.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching])
    }

    // MARK: - Initialized off the main thread

    func test_start_whenCalledOffMainAndLaunchNotificationArrivesBeforeMainQueueRuns_thenReplaysNothing() {
        let subject = createSubject(state: .active)

        startOnBackgroundThread(subject)
        notificationCenter.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        runScheduledOnMainQueue()
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [])
    }

    func test_start_whenCalledOffMainAfterAppBecameActive_thenReplaysLaunchAndBecomeActiveOnMainQueue() {
        let subject = createSubject(state: .active)

        startOnBackgroundThread(subject)
        XCTAssertEqual(callbacksRecorder.callbacks, [])

        runScheduledOnMainQueue()
        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching, .didBecomeActive])
    }

    func test_start_whenCalledOffMainWhileInactiveAndLaunchAlreadyHappened_thenReplaysLaunch() {
        let subject = createSubject(state: .inactive)

        startOnBackgroundThread(subject)
        runScheduledOnMainQueue()
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [.didFinishLaunching])
    }

    // MARK: - No application

    func test_start_whenNoApplicationState_thenReplaysNothing() {
        let subject = createSubject(state: nil)

        subject.start()
        runScheduledOnMainQueue()

        XCTAssertEqual(callbacksRecorder.callbacks, [])
        XCTAssertTrue(scheduledOnMainQueue.isEmpty)
    }
}

private class LifecycleCallbacksRecorder: Plugin, iOSLifecycle {
    enum Callback {
        case didFinishLaunching
        case didBecomeActive
    }

    let type: PluginType = .utility
    var analytics: Analytics?
    private(set) var callbacks: [Callback] = []

    func application(_ application: UIApplication?, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        callbacks.append(.didFinishLaunching)
    }

    func applicationDidBecomeActive(application: UIApplication?) {
        callbacks.append(.didBecomeActive)
    }
}
