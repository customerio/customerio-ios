#if os(iOS)
import CioAnalytics
import Foundation
import UIKit

/// Replays the app launch callbacks to lifecycle plugins when the SDK is initialized after the app already
/// finished launching, which is how React Native and Flutter apps initialize it.
///
/// Segment's lifecycle plugin tracks Application Installed, Application Updated and the first Application Opened
/// only when `UIApplication.didFinishLaunchingNotification` is posted, which happens once per process. An SDK
/// initialized later never receives it, so those events were never tracked for such apps.
///
/// Threading: `start()` reads `UIApplication` state, so it runs on the main thread. When called from another
/// thread it moves itself to the main queue, after it starts listening for the launch notification.
///
/// Memory: callers don't need to keep a reference. A pending main queue check holds the instance until it runs.
final class MissedLaunchLifecycleReplay {
    private let analytics: Analytics
    private let notificationCenter: NotificationCenter
    private let applicationState: () -> UIApplication.State?
    private let runOnMainQueue: (@escaping () -> Void) -> Void

    private var launchNotificationObserver: NSObjectProtocol?
    private var receivedLaunchNotification = false

    init(
        analytics: Analytics,
        notificationCenter: NotificationCenter = .default,
        applicationState: @escaping () -> UIApplication.State? = { MissedLaunchLifecycleReplay.sharedApplication()?.applicationState },
        runOnMainQueue: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.analytics = analytics
        self.notificationCenter = notificationCenter
        self.applicationState = applicationState
        self.runOnMainQueue = runOnMainQueue
    }

    deinit {
        removeLaunchNotificationObserver()
    }

    /// Replays the launch callbacks the SDK missed, if any. Call once while the SDK initializes.
    func start() {
        // Listens before moving to the main queue. The lifecycle plugins started listening while the SDK initialized,
        // so a launch notification posted in the meantime reached them too and must not be replayed.
        launchNotificationObserver = notificationCenter.addObserver(
            forName: UIApplication.didFinishLaunchingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.receivedLaunchNotification = true
        }

        guard Thread.isMainThread else {
            runOnMainQueue { self.replayMissedCallbacks() }
            return
        }
        replayMissedCallbacks()
    }

    private func replayMissedCallbacks() {
        // No application state inside app extensions, so there is no app launch to replay
        guard !receivedLaunchNotification, let state = applicationState() else {
            removeLaunchNotificationObserver()
            return
        }

        if state == .active {
            // The app finished launching and became active before the SDK existed
            removeLaunchNotificationObserver()
            replayDidFinishLaunching()
            replayDidBecomeActive()
            return
        }

        // Inactive or in background, the SDK may be initializing inside application(_:didFinishLaunchingWithOptions:).
        // UIKit posts the launch notification as soon as that method returns and before the main queue runs again,
        // so the lifecycle plugins only missed it if it hasn't arrived by then.
        runOnMainQueue {
            self.removeLaunchNotificationObserver()
            if !self.receivedLaunchNotification {
                self.replayDidFinishLaunching()
            }
        }
    }

    private func replayDidFinishLaunching() {
        let application = Self.sharedApplication()
        analytics.apply { plugin in
            (plugin as? iOSLifecycle)?.application(application, didFinishLaunchingWithOptions: nil)
        }
    }

    private func replayDidBecomeActive() {
        let application = Self.sharedApplication()
        analytics.apply { plugin in
            (plugin as? iOSLifecycle)?.applicationDidBecomeActive(application: application)
        }
    }

    private func removeLaunchNotificationObserver() {
        if let observer = launchNotificationObserver {
            notificationCenter.removeObserver(observer)
            launchNotificationObserver = nil
        }
    }

    /// `UIApplication.shared` without referencing it directly, since it's unavailable in app extensions.
    /// Returns nil in app extensions and in processes without an application, such as unit test runners.
    static func sharedApplication() -> UIApplication? {
        UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication
    }
}
#endif
