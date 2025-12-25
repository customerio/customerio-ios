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

        _ = logManager
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
            sharedAnonymousMessageManager
    }

    var sharedAnonymousMessageManager: AnonymousMessageManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_AnonymousMessageManager_singleton_access").sync {
            if let overridenDep: AnonymousMessageManager = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: AnonymousMessageManager.self)] as? AnonymousMessageManager
            let instance = existingSingletonInstance ?? _get_anonymousMessageManager()
            self.singletons[String(describing: AnonymousMessageManager.self)] = instance
            return instance
        }
    }

    private func _get_anonymousMessageManager() -> AnonymousMessageManager {
        AnonymousMessageManagerImpl(keyValueStorage: sharedKeyValueStorage, dateUtil: dateUtil, logger: logger)
    }

    // SseLifecycleManager (singleton)
    var sseLifecycleManager: SseLifecycleManager {
        getOverriddenInstance() ??
            sharedSseLifecycleManager
    }

    var sharedSseLifecycleManager: SseLifecycleManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_SseLifecycleManager_singleton_access").sync {
            if let overridenDep: SseLifecycleManager = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: SseLifecycleManager.self)] as? SseLifecycleManager
            let instance = existingSingletonInstance ?? _get_sseLifecycleManager()
            self.singletons[String(describing: SseLifecycleManager.self)] = instance
            return instance
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
            sharedGistProvider
    }

    var sharedGistProvider: GistProvider {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_GistProvider_singleton_access").sync {
            if let overridenDep: GistProvider = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: GistProvider.self)] as? GistProvider
            let instance = existingSingletonInstance ?? _get_gistProvider()
            self.singletons[String(describing: GistProvider.self)] = instance
            return instance
        }
    }

    private func _get_gistProvider() -> GistProvider {
        Gist(logger: logger, gistDelegate: gistDelegate, inAppMessageManager: inAppMessageManager, queueManager: queueManager, threadUtil: threadUtil, sseLifecycleManager: sseLifecycleManager)
    }

    // GistDelegate (singleton)
    var gistDelegate: GistDelegate {
        getOverriddenInstance() ??
            sharedGistDelegate
    }

    var sharedGistDelegate: GistDelegate {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_GistDelegate_singleton_access").sync {
            if let overridenDep: GistDelegate = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: GistDelegate.self)] as? GistDelegate
            let instance = existingSingletonInstance ?? _get_gistDelegate()
            self.singletons[String(describing: GistDelegate.self)] = instance
            return instance
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
            sharedInAppMessageManager
    }

    var sharedInAppMessageManager: InAppMessageManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_InAppMessageManager_singleton_access").sync {
            if let overridenDep: InAppMessageManager = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: InAppMessageManager.self)] as? InAppMessageManager
            let instance = existingSingletonInstance ?? _get_inAppMessageManager()
            self.singletons[String(describing: InAppMessageManager.self)] = instance
            return instance
        }
    }

    private func _get_inAppMessageManager() -> InAppMessageManager {
        InAppMessageStoreManager(logger: logger, threadUtil: threadUtil, logManager: logManager, gistDelegate: gistDelegate, anonymousMessageManager: anonymousMessageManager)
    }

    // LogManager
    var logManager: LogManager {
        getOverriddenInstance() ??
            newLogManager
    }

    private var newLogManager: LogManager {
        LogManager(gistQueueNetwork: gistQueueNetwork)
    }

    // QueueManager (singleton)
    var queueManager: QueueManager {
        getOverriddenInstance() ??
            sharedQueueManager
    }

    var sharedQueueManager: QueueManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_QueueManager_singleton_access").sync {
            if let overridenDep: QueueManager = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: QueueManager.self)] as? QueueManager
            let instance = existingSingletonInstance ?? _get_queueManager()
            self.singletons[String(describing: QueueManager.self)] = instance
            return instance
        }
    }

    private func _get_queueManager() -> QueueManager {
        QueueManager(keyValueStore: sharedKeyValueStorage, gistQueueNetwork: gistQueueNetwork, inAppMessageManager: inAppMessageManager, anonymousMessageManager: anonymousMessageManager, logger: logger)
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
            sharedSseConnectionManagerProtocol
    }

    var sharedSseConnectionManagerProtocol: SseConnectionManagerProtocol {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_SseConnectionManagerProtocol_singleton_access").sync {
            if let overridenDep: SseConnectionManagerProtocol = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: SseConnectionManagerProtocol.self)] as? SseConnectionManagerProtocol
            let instance = existingSingletonInstance ?? _get_sseConnectionManagerProtocol()
            self.singletons[String(describing: SseConnectionManagerProtocol.self)] = instance
            return instance
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
            sharedSseServiceProtocol
    }

    var sharedSseServiceProtocol: SseServiceProtocol {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_SseServiceProtocol_singleton_access").sync {
            if let overridenDep: SseServiceProtocol = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: SseServiceProtocol.self)] as? SseServiceProtocol
            let instance = existingSingletonInstance ?? _get_sseServiceProtocol()
            self.singletons[String(describing: SseServiceProtocol.self)] = instance
            return instance
        }
    }

    private func _get_sseServiceProtocol() -> SseServiceProtocol {
        SseService(logger: logger)
    }
}

// swiftlint:enable all
