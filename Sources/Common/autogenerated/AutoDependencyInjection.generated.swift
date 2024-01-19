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
     let wheels = DIGraph.getInstance(siteId: "").offRoadWheels
     // note the name of the property is name of the class with the first letter lowercase.
 }
 ```

 5. How do I use this graph in my test suite?
 ```
 let mockOffRoadWheels = // make a mock of OffRoadWheels class
 DIGraph().override(mockOffRoadWheels, OffRoadWheels.self)
 ```

 Then, when your test function finishes, reset the graph:
 ```
 DIGraph().reset()
 ```

 */

extension DIGraph {
    // call in automated test suite to confirm that all dependnecies able to resolve and not cause runtime exceptions.
    // internal scope so each module can provide their own version of the function with the same name.
    @available(iOSApplicationExtension, unavailable) // some properties could be unavailable to app extensions so this function must also.
    func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = deviceInfo
        countDependenciesResolved += 1

        _ = httpClient
        countDependenciesResolved += 1

        _ = globalDataStore
        countDependenciesResolved += 1

        _ = profileStore
        countDependenciesResolved += 1

        _ = queue
        countDependenciesResolved += 1

        _ = simpleTimer
        countDependenciesResolved += 1

        _ = singleScheduleTimer
        countDependenciesResolved += 1

        _ = threadUtil
        countDependenciesResolved += 1

        _ = logger
        countDependenciesResolved += 1

        _ = httpRetryPolicy
        countDependenciesResolved += 1

        _ = deviceMetricsGrabber
        countDependenciesResolved += 1

        _ = fileStorage
        countDependenciesResolved += 1

        _ = queueStorage
        countDependenciesResolved += 1

        _ = jsonAdapter
        countDependenciesResolved += 1

        _ = lockManager
        countDependenciesResolved += 1

        _ = queueInventoryMemoryStore
        countDependenciesResolved += 1

        _ = dateUtil
        countDependenciesResolved += 1

        _ = uIKitWrapper
        countDependenciesResolved += 1

        _ = httpRequestRunner
        countDependenciesResolved += 1

        _ = userAgentUtil
        countDependenciesResolved += 1

        _ = keyValueStorage
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // DeviceInfo
    public var deviceInfo: DeviceInfo {
        getOverriddenInstance() ??
            newDeviceInfo
    }

    private var newDeviceInfo: DeviceInfo {
        CIODeviceInfo()
    }

    // HttpClient
    public var httpClient: HttpClient {
        getOverriddenInstance() ??
            newHttpClient
    }

    private var newHttpClient: HttpClient {
        CIOHttpClient(sdkConfig: sdkConfig, jsonAdapter: jsonAdapter, httpRequestRunner: httpRequestRunner, globalDataStore: globalDataStore, logger: logger, timer: simpleTimer, retryPolicy: httpRetryPolicy, userAgentUtil: userAgentUtil)
    }

    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {
        getOverriddenInstance() ??
            newGlobalDataStore
    }

    private var newGlobalDataStore: GlobalDataStore {
        CioGlobalDataStore(keyValueStorage: keyValueStorage)
    }

    // ProfileStore
    public var profileStore: ProfileStore {
        getOverriddenInstance() ??
            newProfileStore
    }

    private var newProfileStore: ProfileStore {
        CioProfileStore(keyValueStorage: keyValueStorage)
    }

    // Queue
    public var queue: Queue {
        getOverriddenInstance() ??
            newQueue
    }

    private var newQueue: Queue {
        CioQueue(storage: queueStorage, jsonAdapter: jsonAdapter, logger: logger, sdkConfig: sdkConfig, queueTimer: singleScheduleTimer, dateUtil: dateUtil)
    }

    // SimpleTimer
    var simpleTimer: SimpleTimer {
        getOverriddenInstance() ??
            newSimpleTimer
    }

    private var newSimpleTimer: SimpleTimer {
        CioSimpleTimer(logger: logger)
    }

    // SingleScheduleTimer (singleton)
    var singleScheduleTimer: SingleScheduleTimer {
        getOverriddenInstance() ??
            sharedSingleScheduleTimer
    }

    var sharedSingleScheduleTimer: SingleScheduleTimer {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_SingleScheduleTimer_singleton_access").sync {
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
        CioSingleScheduleTimer(timer: simpleTimer)
    }

    // ThreadUtil
    public var threadUtil: ThreadUtil {
        getOverriddenInstance() ??
            newThreadUtil
    }

    private var newThreadUtil: ThreadUtil {
        CioThreadUtil()
    }

    // Logger
    public var logger: Logger {
        getOverriddenInstance() ??
            newLogger
    }

    private var newLogger: Logger {
        ConsoleLogger(sdkConfig: sdkConfig)
    }

    // HttpRetryPolicy
    var httpRetryPolicy: HttpRetryPolicy {
        getOverriddenInstance() ??
            newHttpRetryPolicy
    }

    private var newHttpRetryPolicy: HttpRetryPolicy {
        CustomerIOAPIHttpRetryPolicy()
    }

    // DeviceMetricsGrabber
    var deviceMetricsGrabber: DeviceMetricsGrabber {
        getOverriddenInstance() ??
            newDeviceMetricsGrabber
    }

    private var newDeviceMetricsGrabber: DeviceMetricsGrabber {
        DeviceMetricsGrabberImpl()
    }

    // FileStorage
    public var fileStorage: FileStorage {
        getOverriddenInstance() ??
            newFileStorage
    }

    private var newFileStorage: FileStorage {
        FileManagerFileStorage(sdkConfig: sdkConfig, logger: logger)
    }

    // QueueStorage
    public var queueStorage: QueueStorage {
        getOverriddenInstance() ??
            newQueueStorage
    }

    private var newQueueStorage: QueueStorage {
        FileManagerQueueStorage(fileStorage: fileStorage, jsonAdapter: jsonAdapter, lockManager: lockManager, sdkConfig: sdkConfig, logger: logger, dateUtil: dateUtil, inventoryStore: queueInventoryMemoryStore)
    }

    // JsonAdapter
    public var jsonAdapter: JsonAdapter {
        getOverriddenInstance() ??
            newJsonAdapter
    }

    private var newJsonAdapter: JsonAdapter {
        JsonAdapter(log: logger)
    }

    // LockManager (singleton)
    public var lockManager: LockManager {
        getOverriddenInstance() ??
            sharedLockManager
    }

    public var sharedLockManager: LockManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_LockManager_singleton_access").sync {
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
        LockManager()
    }

    // QueueInventoryMemoryStore (singleton)
    var queueInventoryMemoryStore: QueueInventoryMemoryStore {
        getOverriddenInstance() ??
            sharedQueueInventoryMemoryStore
    }

    var sharedQueueInventoryMemoryStore: QueueInventoryMemoryStore {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_QueueInventoryMemoryStore_singleton_access").sync {
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
        QueueInventoryMemoryStoreImpl()
    }

    // DateUtil
    public var dateUtil: DateUtil {
        getOverriddenInstance() ??
            newDateUtil
    }

    private var newDateUtil: DateUtil {
        SdkDateUtil()
    }

    // UIKitWrapper
    @available(iOSApplicationExtension, unavailable)
    public var uIKitWrapper: UIKitWrapper {
        getOverriddenInstance() ??
            newUIKitWrapper
    }

    @available(iOSApplicationExtension, unavailable)
    private var newUIKitWrapper: UIKitWrapper {
        UIKitWrapperImpl()
    }

    // HttpRequestRunner
    public var httpRequestRunner: HttpRequestRunner {
        getOverriddenInstance() ??
            newHttpRequestRunner
    }

    private var newHttpRequestRunner: HttpRequestRunner {
        UrlRequestHttpRequestRunner()
    }

    // UserAgentUtil
    public var userAgentUtil: UserAgentUtil {
        getOverriddenInstance() ??
            newUserAgentUtil
    }

    private var newUserAgentUtil: UserAgentUtil {
        UserAgentUtilImpl(deviceInfo: deviceInfo, sdkConfig: sdkConfig)
    }

    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {
        getOverriddenInstance() ??
            newKeyValueStorage
    }

    private var newKeyValueStorage: KeyValueStorage {
        UserDefaultsKeyValueStorage(sdkConfig: sdkConfig, deviceMetricsGrabber: deviceMetricsGrabber)
    }
}

extension DIGraphShared {
    // Handle classes annotated with InjectRegisterShared
    // DeviceInfo
    public var deviceInfo: DeviceInfo {
        getOverriddenInstance() ??
            newDeviceInfo
    }

    private var newDeviceInfo: DeviceInfo {
        CIODeviceInfo()
    }

    // EventBusHandler (singleton)
    public var eventBusHandler: EventBusHandler {
        getOverriddenInstance() ??
            sharedEventBusHandler
    }

    public var sharedEventBusHandler: EventBusHandler {
        DispatchQueue(label: "DIGraphShared_EventBusHandler_singleton_access").sync {
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
        CioEventBusHandler(eventBus: eventBus, eventCache: eventCache, eventStorage: eventStorage, logger: logger)
    }

    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {
        getOverriddenInstance() ??
            newGlobalDataStore
    }

    private var newGlobalDataStore: GlobalDataStore {
        CioSharedDataStore(keyValueStorage: sharedKeyValueStorage)
    }

    // ThreadUtil
    public var threadUtil: ThreadUtil {
        getOverriddenInstance() ??
            newThreadUtil
    }

    private var newThreadUtil: ThreadUtil {
        CioThreadUtil()
    }

    // DeviceMetricsGrabber
    var deviceMetricsGrabber: DeviceMetricsGrabber {
        getOverriddenInstance() ??
            newDeviceMetricsGrabber
    }

    private var newDeviceMetricsGrabber: DeviceMetricsGrabber {
        DeviceMetricsGrabberImpl()
    }

    // EventCache (singleton)
    var eventCache: EventCache {
        getOverriddenInstance() ??
            sharedEventCache
    }

    var sharedEventCache: EventCache {
        DispatchQueue(label: "DIGraphShared_EventCache_singleton_access").sync {
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
        EventCacheManager()
    }

    // EventStorage (singleton)
    var eventStorage: EventStorage {
        getOverriddenInstance() ??
            sharedEventStorage
    }

    var sharedEventStorage: EventStorage {
        DispatchQueue(label: "DIGraphShared_EventStorage_singleton_access").sync {
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
        EventStorageManager(logger: logger, jsonAdapter: jsonAdapter)
    }

    // JsonAdapter
    public var jsonAdapter: JsonAdapter {
        getOverriddenInstance() ??
            newJsonAdapter
    }

    private var newJsonAdapter: JsonAdapter {
        JsonAdapter(log: logger)
    }

    // DateUtil
    public var dateUtil: DateUtil {
        getOverriddenInstance() ??
            newDateUtil
    }

    private var newDateUtil: DateUtil {
        SdkDateUtil()
    }

    // Logger
    public var logger: Logger {
        getOverriddenInstance() ??
            newLogger
    }

    private var newLogger: Logger {
        SharedConsoleLogger()
    }

    // EventBus (singleton)
    var eventBus: EventBus {
        getOverriddenInstance() ??
            sharedEventBus
    }

    var sharedEventBus: EventBus {
        DispatchQueue(label: "DIGraphShared_EventBus_singleton_access").sync {
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
        SharedEventBus()
    }

    // UIKitWrapper
    @available(iOSApplicationExtension, unavailable)
    public var uIKitWrapper: UIKitWrapper {
        getOverriddenInstance() ??
            newUIKitWrapper
    }

    @available(iOSApplicationExtension, unavailable)
    private var newUIKitWrapper: UIKitWrapper {
        UIKitWrapperImpl()
    }

    // HttpRequestRunner
    public var httpRequestRunner: HttpRequestRunner {
        getOverriddenInstance() ??
            newHttpRequestRunner
    }

    private var newHttpRequestRunner: HttpRequestRunner {
        UrlRequestHttpRequestRunner()
    }

    // SharedKeyValueStorage
    public var sharedKeyValueStorage: SharedKeyValueStorage {
        getOverriddenInstance() ??
            newSharedKeyValueStorage
    }

    private var newSharedKeyValueStorage: SharedKeyValueStorage {
        UserDefaultsSharedKeyValueStorage(deviceMetricsGrabber: deviceMetricsGrabber)
    }
}

// swiftlint:enable all
