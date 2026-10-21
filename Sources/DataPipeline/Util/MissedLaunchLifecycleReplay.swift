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
/// thread it moves itself to the main queue, after it starts listening for the lifecycle notifications.
///
/// Memory: callers don't need to keep a reference. A pending main queue check holds the instance until it runs.
final class MissedLaunchLifecycleReplay {
    private let analytics: Analytics
    private let notificationCenter: NotificationCenter
    private let applicationState: () -> UIApplication.State?
    private let runOnMainQueue: (@escaping () -> Void) -> Void

    private var notificationObservers: [NSObjectProtocol] = []
    private var receivedLaunchNotification = false
    private var receivedBecomeActiveNotification = false

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
        removeNotificationObservers()
    }

    /// Replays the launch callbacks the SDK missed, if any. Call once while the SDK initializes.
    func start() {
        // Listens before moving to the main queue. The lifecycle plugins started listening while the SDK initialized,
        // so a notification posted in the meantime reached them too and must not be replayed.
        observe(UIApplication.didFinishLaunchingNotification, setting: \.receivedLaunchNotification)
        observe(UIApplication.didBecomeActiveNotification, setting: \.receivedBecomeActiveNotification)

        guard Thread.isMainThread else {
            runOnMainQueue { self.replayMissedCallbacks() }
            return
        }
        replayMissedCallbacks()
    }

    private func replayMissedCallbacks() {
        // No application state inside app extensions, so there is no app launch to replay
        guard !receivedLaunchNotification, let state = applicationState() else {
            removeNotificationObservers()
            return
        }

        if state == .active {
            // An active app has already posted its launch notification, so it can't arrive anymore
            replayDidFinishLaunching()
        }

        // The SDK may be initializing inside application(_:didFinishLaunchingWithOptions:) while inactive or in
        // background, or inside applicationDidBecomeActive(_:) or sceneDidBecomeActive(_:) while active. UIKit posts
        // the matching notification as soon as that method returns and before the main queue runs again, so the
        // lifecycle plugins only missed it if it hasn't arrived by then.
        runOnMainQueue {
            self.removeNotificationObservers()
            if state == .active {
                if !self.receivedBecomeActiveNotification {
                    self.replayDidBecomeActive()
                }
            } else if !self.receivedLaunchNotification {
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

    private func observe(_ name: Notification.Name, setting flag: ReferenceWritableKeyPath<MissedLaunchLifecycleReplay, Bool>) {
        let observer = notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?[keyPath: flag] = true
        }
        notificationObservers.append(observer)
    }

    private func removeNotificationObservers() {
        notificationObservers.forEach { notificationCenter.removeObserver($0) }
        notificationObservers.removeAll()
    }

    /// `UIApplication.shared` without referencing it directly, since it's unavailable in app extensions.
    /// Returns nil in app extensions and in processes without an application, such as unit test runners.
    static func sharedApplication() -> UIApplication? {
        UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication
    }
}
#endif
