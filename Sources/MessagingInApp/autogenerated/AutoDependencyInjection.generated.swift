// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import CioInternalCommon
import Foundation
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
    func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = anonymousMessageManager
        countDependenciesResolved += 1

        _ = sseLifecycleManager
        countDependenciesResolved += 1

        _ = engineWebProvider
        countDependenciesResolved += 1

        _ = gistProvider
        countDependenciesResolved += 1

        _ = gistDelegate
        countDependenciesResolved += 1

        _ = gistQueueNetwork
        countDependenciesResolved += 1

        _ = heartbeatTimerProtocol
        countDependenciesResolved += 1

        _ = inAppMessageManager
        countDependenciesResolved += 1

        _ = inboxMessageCacheManager
        countDependenciesResolved += 1

        _ = logManager
        countDependenciesResolved += 1

        _ = messageInboxInstance
        countDependenciesResolved += 1

        _ = queueManager
        countDependenciesResolved += 1

        _ = applicationStateProvider
        countDependenciesResolved += 1

        _ = sleeper
        countDependenciesResolved += 1

        _ = sseConnectionManagerProtocol
        countDependenciesResolved += 1

        _ = sseRetryHelperProtocol
        countDependenciesResolved += 1

        _ = sseServiceProtocol
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // AnonymousMessageManager (singleton)
    var anonymousMessageManager: AnonymousMessageManager {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_anonymousMessageManager()
            }
    }

    private func _get_anonymousMessageManager() -> AnonymousMessageManager {
        AnonymousMessageManagerImpl(keyValueStorage: sharedKeyValueStorage, dateUtil: dateUtil, logger: logger)
    }

    // SseLifecycleManager (singleton)
    var sseLifecycleManager: SseLifecycleManager {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_sseLifecycleManager()
            }
    }

    private func _get_sseLifecycleManager() -> SseLifecycleManager {
        CioSseLifecycleManager(logger: logger, inAppMessageManager: inAppMessageManager, sseConnectionManager: sseConnectionManagerProtocol, applicationStateProvider: applicationStateProvider)
    }

    // EngineWebProvider
    var engineWebProvider: EngineWebProvider {
        getOverriddenInstance() ??
            newEngineWebProvider
    }

    private var newEngineWebProvider: EngineWebProvider {
        EngineWebProviderImpl()
    }

    // GistProvider (singleton)
    var gistProvider: GistProvider {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_gistProvider()
            }
    }

    private func _get_gistProvider() -> GistProvider {
        Gist(logger: logger, gistDelegate: gistDelegate, inAppMessageManager: inAppMessageManager, queueManager: queueManager, threadUtil: threadUtil, sseLifecycleManager: sseLifecycleManager)
    }

    // GistDelegate (singleton)
    var gistDelegate: GistDelegate {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_gistDelegate()
            }
    }

    private func _get_gistDelegate() -> GistDelegate {
        GistDelegateImpl(logger: logger, eventBusHandler: eventBusHandler)
    }

    // GistQueueNetwork
    var gistQueueNetwork: GistQueueNetwork {
        getOverriddenInstance() ??
            newGistQueueNetwork
    }

    private var newGistQueueNetwork: GistQueueNetwork {
        GistQueueNetworkImpl()
    }

    // HeartbeatTimerProtocol
    var heartbeatTimerProtocol: HeartbeatTimerProtocol {
        getOverriddenInstance() ??
            newHeartbeatTimerProtocol
    }

    private var newHeartbeatTimerProtocol: HeartbeatTimerProtocol {
        HeartbeatTimer(logger: logger)
    }

    // InAppMessageManager (singleton)
    var inAppMessageManager: InAppMessageManager {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_inAppMessageManager()
            }
    }

    private func _get_inAppMessageManager() -> InAppMessageManager {
        InAppMessageStoreManager(logger: logger, threadUtil: threadUtil, logManager: logManager, gistDelegate: gistDelegate, anonymousMessageManager: anonymousMessageManager, eventBusHandler: eventBusHandler)
    }

    // InboxMessageCacheManager (singleton)
    var inboxMessageCacheManager: InboxMessageCacheManager {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_inboxMessageCacheManager()
            }
    }

    private func _get_inboxMessageCacheManager() -> InboxMessageCacheManager {
        InboxMessageCacheManager(keyValueStore: sharedKeyValueStorage, logger: logger)
    }

    // LogManager
    var logManager: LogManager {
        getOverriddenInstance() ??
            newLogManager
    }

    private var newLogManager: LogManager {
        LogManager(gistQueueNetwork: gistQueueNetwork, inboxMessageCache: inboxMessageCacheManager)
    }

    // MessageInboxInstance (singleton)
    var messageInboxInstance: MessageInboxInstance {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_messageInboxInstance()
            }
    }

    private func _get_messageInboxInstance() -> MessageInboxInstance {
        MessageInbox(logger: logger, inAppMessageManager: inAppMessageManager)
    }

    // QueueManager (singleton)
    var queueManager: QueueManager {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_queueManager()
            }
    }

    private func _get_queueManager() -> QueueManager {
        QueueManager(keyValueStore: sharedKeyValueStorage, gistQueueNetwork: gistQueueNetwork, inAppMessageManager: inAppMessageManager, anonymousMessageManager: anonymousMessageManager, inboxMessageCache: inboxMessageCacheManager, logger: logger)
    }

    // ApplicationStateProvider
    var applicationStateProvider: ApplicationStateProvider {
        getOverriddenInstance() ??
            newApplicationStateProvider
    }

    private var newApplicationStateProvider: ApplicationStateProvider {
        RealApplicationStateProvider()
    }

    // Sleeper
    var sleeper: Sleeper {
        getOverriddenInstance() ??
            newSleeper
    }

    private var newSleeper: Sleeper {
        RealSleeper()
    }

    // SseConnectionManagerProtocol (singleton)
    var sseConnectionManagerProtocol: SseConnectionManagerProtocol {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_sseConnectionManagerProtocol()
            }
    }

    private func _get_sseConnectionManagerProtocol() -> SseConnectionManagerProtocol {
        SseConnectionManager(logger: logger, inAppMessageManager: inAppMessageManager, sseService: sseServiceProtocol, retryHelper: sseRetryHelperProtocol, heartbeatTimer: heartbeatTimerProtocol)
    }

    // SseRetryHelperProtocol
    var sseRetryHelperProtocol: SseRetryHelperProtocol {
        getOverriddenInstance() ??
            newSseRetryHelperProtocol
    }

    private var newSseRetryHelperProtocol: SseRetryHelperProtocol {
        SseRetryHelper(logger: logger, sleeper: sleeper)
    }

    // SseServiceProtocol (singleton)
    var sseServiceProtocol: SseServiceProtocol {
        getOverriddenInstance() ??
            getSingletonOrCreate {
                _get_sseServiceProtocol()
            }
    }

    private func _get_sseServiceProtocol() -> SseServiceProtocol {
        SseService(logger: logger)
    }
}

// swiftlint:enable all
