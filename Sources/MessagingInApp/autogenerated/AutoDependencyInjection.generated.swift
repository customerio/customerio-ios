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

        _ = self.engineWebProvider
        countDependenciesResolved += 1

        _ = self.gistProvider
        countDependenciesResolved += 1

        _ = self.gistDelegate
        countDependenciesResolved += 1

        _ = self.gistQueueNetwork
        countDependenciesResolved += 1

        _ = self.inAppMessageManager
        countDependenciesResolved += 1

        _ = self.logManager
        countDependenciesResolved += 1

        _ = self.queueManager
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
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
            self.sharedGistProvider
    }
    internal var sharedGistProvider: GistProvider {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_GistProvider_singleton_access").sync {
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
        return Gist(logger: self.logger, gistDelegate: self.gistDelegate, inAppMessageManager: self.inAppMessageManager, queueManager: self.queueManager, threadUtil: self.threadUtil)
    }
    // GistDelegate (singleton)
    internal var gistDelegate: GistDelegate {
        return getOverriddenInstance() ??
            self.sharedGistDelegate
    }
    internal var sharedGistDelegate: GistDelegate {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_GistDelegate_singleton_access").sync {
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
    // InAppMessageManager (singleton)
    internal var inAppMessageManager: InAppMessageManager {
        return getOverriddenInstance() ??
            self.sharedInAppMessageManager
    }
    internal var sharedInAppMessageManager: InAppMessageManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_InAppMessageManager_singleton_access").sync {
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
        return InAppMessageStoreManager(logger: self.logger, threadUtil: self.threadUtil, logManager: self.logManager, gistDelegate: self.gistDelegate)
    }
    // LogManager
    internal var logManager: LogManager {
        return getOverriddenInstance() ??
            self.newLogManager
    }
    private var newLogManager: LogManager {
        return LogManager(gistQueueNetwork: self.gistQueueNetwork)
    }
    // QueueManager (singleton)
    internal var queueManager: QueueManager {
        return getOverriddenInstance() ??
            self.sharedQueueManager
    }
    internal var sharedQueueManager: QueueManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_QueueManager_singleton_access").sync {
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
        return QueueManager(keyValueStore: self.sharedKeyValueStorage, gistQueueNetwork: self.gistQueueNetwork, inAppMessageManager: self.inAppMessageManager, logger: self.logger)
    }
}

// swiftlint:enable all
