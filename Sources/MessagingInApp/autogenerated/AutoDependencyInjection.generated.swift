// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
import CioInternalCommon
import UIKit

/**
######################################################
Documentation
######################################################

This automatically generated file you are viewing is a dependency injection graph for your app's source code.
You may be wondering a couple of questions.

1. How did this file get generated? Answer --> https://github.com/levibostian/Sourcery-DI#how
2. Why use this dependency injection graph instead of X other solution/tool? Answer --> https://github.com/levibostian/Sourcery-DI#why-use-this-project
3. How do I add dependencies to this graph file? Follow one of the instructions below:
* Add a non singleton class: https://github.com/levibostian/Sourcery-DI#add-a-non-singleton-class
* Add a generic class: https://github.com/levibostian/Sourcery-DI#add-a-generic-class
* Add a singleton class: https://github.com/levibostian/Sourcery-DI#add-a-singleton-class
* Add a class from a 3rd party library/SDK: https://github.com/levibostian/Sourcery-DI#add-a-class-from-a-3rd-party
* Add a `typealias` https://github.com/levibostian/Sourcery-DI#add-a-typealias

4. How do I get dependencies from the graph in my code?
```
// If you have a class like this:
class OffRoadWheels {}

class ViewController: UIViewController {
    // Call the property getter to get your dependency from the graph:
    let wheels = DIGraphShared.shared.offRoadWheels
    // note the name of the property is name of the class with the first letter lowercase.
}
```

5. How do I use this graph in my test suite?
```
let mockOffRoadWheels = // make a mock of OffRoadWheels class
DIGraphShared.shared.override(mockOffRoadWheels, OffRoadWheels.self)
```

Then, when your test function finishes, reset the graph:
```
DIGraphShared.shared.reset()
```

*/



extension DIGraphShared {
    // call in automated test suite to confirm that all dependnecies able to resolve and not cause runtime exceptions.
    // internal scope so each module can provide their own version of the function with the same name.
    @available(iOSApplicationExtension, unavailable) // some properties could be unavailable to app extensions so this function must also.
    internal func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = self.anonymousMessageManager
        countDependenciesResolved += 1

        _ = self.sseLifecycleManager
        countDependenciesResolved += 1

        _ = self.notificationInbox
        countDependenciesResolved += 1

        _ = self.engineWebProvider
        countDependenciesResolved += 1

        _ = self.gistProvider
        countDependenciesResolved += 1

        _ = self.gistDelegate
        countDependenciesResolved += 1

        _ = self.gistQueueNetwork
        countDependenciesResolved += 1

        _ = self.heartbeatTimerProtocol
        countDependenciesResolved += 1

        _ = self.inAppMessageManager
        countDependenciesResolved += 1

        _ = self.inboxMessageCacheManager
        countDependenciesResolved += 1

        _ = self.logManager
        countDependenciesResolved += 1

        _ = self.queueManager
        countDependenciesResolved += 1

        _ = self.applicationStateProvider
        countDependenciesResolved += 1

        _ = self.sleeper
        countDependenciesResolved += 1

        _ = self.sseConnectionManagerProtocol
        countDependenciesResolved += 1

        _ = self.sseRetryHelperProtocol
        countDependenciesResolved += 1

        _ = self.sseServiceProtocol
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // AnonymousMessageManager (singleton)
    internal var anonymousMessageManager: AnonymousMessageManager {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_anonymousMessageManager()
            }
    }
    private func _get_anonymousMessageManager() -> AnonymousMessageManager {
        return AnonymousMessageManagerImpl(keyValueStorage: self.sharedKeyValueStorage, dateUtil: self.dateUtil, logger: self.logger)
    }
    // SseLifecycleManager (singleton)
    internal var sseLifecycleManager: SseLifecycleManager {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_sseLifecycleManager()
            }
    }
    private func _get_sseLifecycleManager() -> SseLifecycleManager {
        return CioSseLifecycleManager(logger: self.logger, inAppMessageManager: self.inAppMessageManager, sseConnectionManager: self.sseConnectionManagerProtocol, applicationStateProvider: self.applicationStateProvider)
    }
    // NotificationInbox (singleton)
    internal var notificationInbox: NotificationInbox {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_notificationInbox()
            }
    }
    private func _get_notificationInbox() -> NotificationInbox {
        return DefaultNotificationInbox(logger: self.logger, inAppMessageManager: self.inAppMessageManager)
    }
    // EngineWebProvider
    internal var engineWebProvider: EngineWebProvider {
        return getOverriddenInstance() ??
            self.newEngineWebProvider
    }
    private var newEngineWebProvider: EngineWebProvider {
        return EngineWebProviderImpl()
    }
    // GistProvider (singleton)
    internal var gistProvider: GistProvider {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_gistProvider()
            }
    }
    private func _get_gistProvider() -> GistProvider {
        return Gist(logger: self.logger, gistDelegate: self.gistDelegate, inAppMessageManager: self.inAppMessageManager, queueManager: self.queueManager, threadUtil: self.threadUtil, sseLifecycleManager: self.sseLifecycleManager)
    }
    // GistDelegate (singleton)
    internal var gistDelegate: GistDelegate {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_gistDelegate()
            }
    }
    private func _get_gistDelegate() -> GistDelegate {
        return GistDelegateImpl(logger: self.logger, eventBusHandler: self.eventBusHandler)
    }
    // GistQueueNetwork
    internal var gistQueueNetwork: GistQueueNetwork {
        return getOverriddenInstance() ??
            self.newGistQueueNetwork
    }
    private var newGistQueueNetwork: GistQueueNetwork {
        return GistQueueNetworkImpl()
    }
    // HeartbeatTimerProtocol
    internal var heartbeatTimerProtocol: HeartbeatTimerProtocol {
        return getOverriddenInstance() ??
            self.newHeartbeatTimerProtocol
    }
    private var newHeartbeatTimerProtocol: HeartbeatTimerProtocol {
        return HeartbeatTimer(logger: self.logger)
    }
    // InAppMessageManager (singleton)
    internal var inAppMessageManager: InAppMessageManager {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_inAppMessageManager()
            }
    }
    private func _get_inAppMessageManager() -> InAppMessageManager {
        return InAppMessageStoreManager(logger: self.logger, threadUtil: self.threadUtil, logManager: self.logManager, gistDelegate: self.gistDelegate, anonymousMessageManager: self.anonymousMessageManager, eventBusHandler: self.eventBusHandler)
    }
    // InboxMessageCacheManager (singleton)
    internal var inboxMessageCacheManager: InboxMessageCacheManager {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_inboxMessageCacheManager()
            }
    }
    private func _get_inboxMessageCacheManager() -> InboxMessageCacheManager {
        return InboxMessageCacheManager(keyValueStore: self.sharedKeyValueStorage, logger: self.logger)
    }
    // LogManager
    internal var logManager: LogManager {
        return getOverriddenInstance() ??
            self.newLogManager
    }
    private var newLogManager: LogManager {
        return LogManager(gistQueueNetwork: self.gistQueueNetwork, inboxMessageCache: self.inboxMessageCacheManager)
    }
    // QueueManager (singleton)
    internal var queueManager: QueueManager {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_queueManager()
            }
    }
    private func _get_queueManager() -> QueueManager {
        return QueueManager(keyValueStore: self.sharedKeyValueStorage, gistQueueNetwork: self.gistQueueNetwork, inAppMessageManager: self.inAppMessageManager, anonymousMessageManager: self.anonymousMessageManager, inboxMessageCache: self.inboxMessageCacheManager, logger: self.logger)
    }
    // ApplicationStateProvider
    internal var applicationStateProvider: ApplicationStateProvider {
        return getOverriddenInstance() ??
            self.newApplicationStateProvider
    }
    private var newApplicationStateProvider: ApplicationStateProvider {
        return RealApplicationStateProvider()
    }
    // Sleeper
    internal var sleeper: Sleeper {
        return getOverriddenInstance() ??
            self.newSleeper
    }
    private var newSleeper: Sleeper {
        return RealSleeper()
    }
    // SseConnectionManagerProtocol (singleton)
    internal var sseConnectionManagerProtocol: SseConnectionManagerProtocol {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_sseConnectionManagerProtocol()
            }
    }
    private func _get_sseConnectionManagerProtocol() -> SseConnectionManagerProtocol {
        return SseConnectionManager(logger: self.logger, inAppMessageManager: self.inAppMessageManager, sseService: self.sseServiceProtocol, retryHelper: self.sseRetryHelperProtocol, heartbeatTimer: self.heartbeatTimerProtocol)
    }
    // SseRetryHelperProtocol
    internal var sseRetryHelperProtocol: SseRetryHelperProtocol {
        return getOverriddenInstance() ??
            self.newSseRetryHelperProtocol
    }
    private var newSseRetryHelperProtocol: SseRetryHelperProtocol {
        return SseRetryHelper(logger: self.logger, sleeper: self.sleeper)
    }
    // SseServiceProtocol (singleton)
    internal var sseServiceProtocol: SseServiceProtocol {
        return getOverriddenInstance() ??
            getSingletonOrCreate() {
                _get_sseServiceProtocol()
            }
    }
    private func _get_sseServiceProtocol() -> SseServiceProtocol {
        return SseService(logger: self.logger)
    }
}

// swiftlint:enable all
