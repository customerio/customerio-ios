// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation

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

        _ = self.deviceInfo
        countDependenciesResolved += 1

        _ = self.eventBusHandler
        countDependenciesResolved += 1

        _ = self.profileStore
        countDependenciesResolved += 1

        _ = self.queue
        countDependenciesResolved += 1

        _ = self.globalDataStore
        countDependenciesResolved += 1

        _ = self.simpleTimer
        countDependenciesResolved += 1

        _ = self.singleScheduleTimer
        countDependenciesResolved += 1

        _ = self.threadUtil
        countDependenciesResolved += 1

        _ = self.logger
        countDependenciesResolved += 1

        _ = self.sdkClient
        countDependenciesResolved += 1

        _ = self.deepLinkUtil
        countDependenciesResolved += 1

        _ = self.deviceMetricsGrabber
        countDependenciesResolved += 1

        _ = self.eventBusObserversHolder
        countDependenciesResolved += 1

        _ = self.eventCache
        countDependenciesResolved += 1

        _ = self.eventStorage
        countDependenciesResolved += 1

        _ = self.fileStorage
        countDependenciesResolved += 1

        _ = self.queueStorage
        countDependenciesResolved += 1

        _ = self.jsonAdapter
        countDependenciesResolved += 1

        _ = self.lockManager
        countDependenciesResolved += 1

        _ = self.queueInventoryMemoryStore
        countDependenciesResolved += 1

        _ = self.dateUtil
        countDependenciesResolved += 1

        _ = self.eventBus
        countDependenciesResolved += 1

        _ = self.uIKitWrapper
        countDependenciesResolved += 1

        _ = self.httpRequestRunner
        countDependenciesResolved += 1

        _ = self.userAgentUtil
        countDependenciesResolved += 1

        _ = self.sandboxedSiteIdKeyValueStorage
        countDependenciesResolved += 1

        _ = self.sharedKeyValueStorage
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // DeviceInfo
    public var deviceInfo: DeviceInfo {
        return getOverriddenInstance() ??
            self.newDeviceInfo
    }
    private var newDeviceInfo: DeviceInfo {
        return CIODeviceInfo()
    }
    // EventBusHandler (singleton)
    public var eventBusHandler: EventBusHandler {
        return getOverriddenInstance() ??
            self.sharedEventBusHandler
    }
    public var sharedEventBusHandler: EventBusHandler {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_EventBusHandler_singleton_access").sync {
            if let overridenDep: EventBusHandler = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: EventBusHandler.self)] as? EventBusHandler
            let instance = existingSingletonInstance ?? _get_eventBusHandler()
            self.singletons[String(describing: EventBusHandler.self)] = instance
            return instance
        }
    }
    private func _get_eventBusHandler() -> EventBusHandler {
        return CioEventBusHandler(eventBus: self.eventBus, eventCache: self.eventCache, eventStorage: self.eventStorage, logger: self.logger)
    }
    // ProfileStore
    public var profileStore: ProfileStore {
        return getOverriddenInstance() ??
            self.newProfileStore
    }
    private var newProfileStore: ProfileStore {
        return CioProfileStore(keyValueStorage: self.sandboxedSiteIdKeyValueStorage)
    }
    // Queue
    public var queue: Queue {
        return getOverriddenInstance() ??
            self.newQueue
    }
    private var newQueue: Queue {
        return CioQueue(storage: self.queueStorage, jsonAdapter: self.jsonAdapter, logger: self.logger, queueTimer: self.singleScheduleTimer, dateUtil: self.dateUtil)
    }
    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {
        return getOverriddenInstance() ??
            self.newGlobalDataStore
    }
    private var newGlobalDataStore: GlobalDataStore {
        return CioSharedDataStore(keyValueStorage: self.sharedKeyValueStorage)
    }
    // SimpleTimer
    internal var simpleTimer: SimpleTimer {
        return getOverriddenInstance() ??
            self.newSimpleTimer
    }
    private var newSimpleTimer: SimpleTimer {
        return CioSimpleTimer(logger: self.logger)
    }
    // SingleScheduleTimer (singleton)
    internal var singleScheduleTimer: SingleScheduleTimer {
        return getOverriddenInstance() ??
            self.sharedSingleScheduleTimer
    }
    internal var sharedSingleScheduleTimer: SingleScheduleTimer {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_SingleScheduleTimer_singleton_access").sync {
            if let overridenDep: SingleScheduleTimer = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: SingleScheduleTimer.self)] as? SingleScheduleTimer
            let instance = existingSingletonInstance ?? _get_singleScheduleTimer()
            self.singletons[String(describing: SingleScheduleTimer.self)] = instance
            return instance
        }
    }
    private func _get_singleScheduleTimer() -> SingleScheduleTimer {
        return CioSingleScheduleTimer(timer: self.simpleTimer)
    }
    // ThreadUtil
    public var threadUtil: ThreadUtil {
        return getOverriddenInstance() ??
            self.newThreadUtil
    }
    private var newThreadUtil: ThreadUtil {
        return CioThreadUtil()
    }
    // Logger (singleton)
    public var logger: Logger {
        return getOverriddenInstance() ??
            self.sharedLogger
    }
    public var sharedLogger: Logger {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_Logger_singleton_access").sync {
            if let overridenDep: Logger = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: Logger.self)] as? Logger
            let instance = existingSingletonInstance ?? _get_logger()
            self.singletons[String(describing: Logger.self)] = instance
            return instance
        }
    }
    private func _get_logger() -> Logger {
        return ConsoleLogger()
    }
    // SdkClient (custom. property getter provided via extension)
    public var sdkClient: SdkClient {
        return getOverriddenInstance() ??
            self.customSdkClient
    }
    // DeepLinkUtil
    @available(iOSApplicationExtension, unavailable)
    public var deepLinkUtil: DeepLinkUtil {
        return getOverriddenInstance() ??
            self.newDeepLinkUtil
    }
    @available(iOSApplicationExtension, unavailable)
    private var newDeepLinkUtil: DeepLinkUtil {
        return DeepLinkUtilImpl(logger: self.logger, uiKitWrapper: self.uIKitWrapper)
    }
    // DeviceMetricsGrabber
    internal var deviceMetricsGrabber: DeviceMetricsGrabber {
        return getOverriddenInstance() ??
            self.newDeviceMetricsGrabber
    }
    private var newDeviceMetricsGrabber: DeviceMetricsGrabber {
        return DeviceMetricsGrabberImpl()
    }
    // EventBusObserversHolder (singleton)
    internal var eventBusObserversHolder: EventBusObserversHolder {
        return getOverriddenInstance() ??
            self.sharedEventBusObserversHolder
    }
    internal var sharedEventBusObserversHolder: EventBusObserversHolder {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_EventBusObserversHolder_singleton_access").sync {
            if let overridenDep: EventBusObserversHolder = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: EventBusObserversHolder.self)] as? EventBusObserversHolder
            let instance = existingSingletonInstance ?? _get_eventBusObserversHolder()
            self.singletons[String(describing: EventBusObserversHolder.self)] = instance
            return instance
        }
    }
    private func _get_eventBusObserversHolder() -> EventBusObserversHolder {
        return EventBusObserversHolder()
    }
    // EventCache (singleton)
    internal var eventCache: EventCache {
        return getOverriddenInstance() ??
            self.sharedEventCache
    }
    internal var sharedEventCache: EventCache {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_EventCache_singleton_access").sync {
            if let overridenDep: EventCache = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: EventCache.self)] as? EventCache
            let instance = existingSingletonInstance ?? _get_eventCache()
            self.singletons[String(describing: EventCache.self)] = instance
            return instance
        }
    }
    private func _get_eventCache() -> EventCache {
        return EventCacheManager()
    }
    // EventStorage (singleton)
    internal var eventStorage: EventStorage {
        return getOverriddenInstance() ??
            self.sharedEventStorage
    }
    internal var sharedEventStorage: EventStorage {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_EventStorage_singleton_access").sync {
            if let overridenDep: EventStorage = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: EventStorage.self)] as? EventStorage
            let instance = existingSingletonInstance ?? _get_eventStorage()
            self.singletons[String(describing: EventStorage.self)] = instance
            return instance
        }
    }
    private func _get_eventStorage() -> EventStorage {
        return EventStorageManager(logger: self.logger, jsonAdapter: self.jsonAdapter)
    }
    // FileStorage
    public var fileStorage: FileStorage {
        return getOverriddenInstance() ??
            self.newFileStorage
    }
    private var newFileStorage: FileStorage {
        return FileManagerFileStorage(logger: self.logger)
    }
    // QueueStorage
    public var queueStorage: QueueStorage {
        return getOverriddenInstance() ??
            self.newQueueStorage
    }
    private var newQueueStorage: QueueStorage {
        return FileManagerQueueStorage(fileStorage: self.fileStorage, jsonAdapter: self.jsonAdapter, lockManager: self.lockManager, logger: self.logger, dateUtil: self.dateUtil, inventoryStore: self.queueInventoryMemoryStore)
    }
    // JsonAdapter
    public var jsonAdapter: JsonAdapter {
        return getOverriddenInstance() ??
            self.newJsonAdapter
    }
    private var newJsonAdapter: JsonAdapter {
        return JsonAdapter(log: self.logger)
    }
    // LockManager (singleton)
    public var lockManager: LockManager {
        return getOverriddenInstance() ??
            self.sharedLockManager
    }
    public var sharedLockManager: LockManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_LockManager_singleton_access").sync {
            if let overridenDep: LockManager = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: LockManager.self)] as? LockManager
            let instance = existingSingletonInstance ?? _get_lockManager()
            self.singletons[String(describing: LockManager.self)] = instance
            return instance
        }
    }
    private func _get_lockManager() -> LockManager {
        return LockManager()
    }
    // QueueInventoryMemoryStore (singleton)
    internal var queueInventoryMemoryStore: QueueInventoryMemoryStore {
        return getOverriddenInstance() ??
            self.sharedQueueInventoryMemoryStore
    }
    internal var sharedQueueInventoryMemoryStore: QueueInventoryMemoryStore {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_QueueInventoryMemoryStore_singleton_access").sync {
            if let overridenDep: QueueInventoryMemoryStore = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: QueueInventoryMemoryStore.self)] as? QueueInventoryMemoryStore
            let instance = existingSingletonInstance ?? _get_queueInventoryMemoryStore()
            self.singletons[String(describing: QueueInventoryMemoryStore.self)] = instance
            return instance
        }
    }
    private func _get_queueInventoryMemoryStore() -> QueueInventoryMemoryStore {
        return QueueInventoryMemoryStoreImpl()
    }
    // DateUtil
    public var dateUtil: DateUtil {
        return getOverriddenInstance() ??
            self.newDateUtil
    }
    private var newDateUtil: DateUtil {
        return SdkDateUtil()
    }
    // EventBus (singleton)
    internal var eventBus: EventBus {
        return getOverriddenInstance() ??
            self.sharedEventBus
    }
    internal var sharedEventBus: EventBus {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_EventBus_singleton_access").sync {
            if let overridenDep: EventBus = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: EventBus.self)] as? EventBus
            let instance = existingSingletonInstance ?? _get_eventBus()
            self.singletons[String(describing: EventBus.self)] = instance
            return instance
        }
    }
    private func _get_eventBus() -> EventBus {
        return SharedEventBus(holder: self.eventBusObserversHolder)
    }
    // UIKitWrapper
    @available(iOSApplicationExtension, unavailable)
    public var uIKitWrapper: UIKitWrapper {
        return getOverriddenInstance() ??
            self.newUIKitWrapper
    }
    @available(iOSApplicationExtension, unavailable)
    private var newUIKitWrapper: UIKitWrapper {
        return UIKitWrapperImpl()
    }
    // HttpRequestRunner
    public var httpRequestRunner: HttpRequestRunner {
        return getOverriddenInstance() ??
            self.newHttpRequestRunner
    }
    private var newHttpRequestRunner: HttpRequestRunner {
        return UrlRequestHttpRequestRunner()
    }
    // UserAgentUtil
    public var userAgentUtil: UserAgentUtil {
        return getOverriddenInstance() ??
            self.newUserAgentUtil
    }
    private var newUserAgentUtil: UserAgentUtil {
        return UserAgentUtilImpl(deviceInfo: self.deviceInfo, sdkClient: self.sdkClient)
    }
    // SandboxedSiteIdKeyValueStorage
    public var sandboxedSiteIdKeyValueStorage: SandboxedSiteIdKeyValueStorage {
        return getOverriddenInstance() ??
            self.newSandboxedSiteIdKeyValueStorage
    }
    private var newSandboxedSiteIdKeyValueStorage: SandboxedSiteIdKeyValueStorage {
        return UserDefaultsSandboxedSiteIdKVStore(deviceMetricsGrabber: self.deviceMetricsGrabber)
    }
    // SharedKeyValueStorage
    public var sharedKeyValueStorage: SharedKeyValueStorage {
        return getOverriddenInstance() ??
            self.newSharedKeyValueStorage
    }
    private var newSharedKeyValueStorage: SharedKeyValueStorage {
        return UserDefaultsSharedKeyValueStorage(deviceMetricsGrabber: self.deviceMetricsGrabber)
    }
}

// swiftlint:enable all
