// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
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

public extension DIGraph {
    // call in automated test suite to confirm that all dependnecies able to resolve and not cause runtime exceptions.
    // internal scope so each module can provide their own version of the function with the same name.
    internal func testDependenciesAbleToResolve() {
        _ = deviceInfo
        _ = httpClient
        _ = sdkCredentialsStore
        _ = globalDataStore
        _ = hooksManager
        _ = profileStore
        _ = queue
        _ = queueQueryRunner
        _ = queueRequestManager
        _ = queueRunRequest
        _ = queueRunner
        _ = simpleTimer
        _ = singleScheduleTimer
        _ = threadUtil
        _ = logger
        _ = httpRetryPolicy
        _ = fileStorage
        _ = queueStorage
        _ = activeWorkspacesManager
        _ = sdkConfigStore
        _ = jsonAdapter
        _ = lockManager
        _ = dateUtil
        _ = httpRequestRunner
        _ = keyValueStorage
    }

    // DeviceInfo
    var deviceInfo: DeviceInfo {
        if let overridenDep = overrides[String(describing: DeviceInfo.self)] {
            return overridenDep as! DeviceInfo
        }
        return newDeviceInfo
    }

    private var newDeviceInfo: DeviceInfo {
        CIODeviceInfo()
    }

    // HttpClient
    var httpClient: HttpClient {
        if let overridenDep = overrides[String(describing: HttpClient.self)] {
            return overridenDep as! HttpClient
        }
        return newHttpClient
    }

    private var newHttpClient: HttpClient {
        CIOHttpClient(siteId: siteId, sdkCredentialsStore: sdkCredentialsStore, configStore: sdkConfigStore,
                      jsonAdapter: jsonAdapter, httpRequestRunner: httpRequestRunner, globalDataStore: globalDataStore,
                      logger: logger, timer: simpleTimer, retryPolicy: httpRetryPolicy, deviceInfo: deviceInfo)
    }

    // SdkCredentialsStore
    var sdkCredentialsStore: SdkCredentialsStore {
        if let overridenDep = overrides[String(describing: SdkCredentialsStore.self)] {
            return overridenDep as! SdkCredentialsStore
        }
        return newSdkCredentialsStore
    }

    private var newSdkCredentialsStore: SdkCredentialsStore {
        CIOSdkCredentialsStore(keyValueStorage: keyValueStorage)
    }

    // GlobalDataStore (singleton)
    var globalDataStore: GlobalDataStore {
        if let overridenDep = overrides[String(describing: GlobalDataStore.self)] {
            return overridenDep as! GlobalDataStore
        }
        return sharedGlobalDataStore
    }

    var sharedGlobalDataStore: GlobalDataStore {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_GlobalDataStore_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: GlobalDataStore.self)] {
                return overridenDep as! GlobalDataStore
            }
            let existingSingletonInstance = self
                .singletons[String(describing: GlobalDataStore.self)] as? GlobalDataStore
            let instance = existingSingletonInstance ?? _get_globalDataStore()
            self.singletons[String(describing: GlobalDataStore.self)] = instance
            return instance
        }
    }

    private func _get_globalDataStore() -> GlobalDataStore {
        CioGlobalDataStore()
    }

    // HooksManager (singleton)
    var hooksManager: HooksManager {
        if let overridenDep = overrides[String(describing: HooksManager.self)] {
            return overridenDep as! HooksManager
        }
        return sharedHooksManager
    }

    var sharedHooksManager: HooksManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_HooksManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: HooksManager.self)] {
                return overridenDep as! HooksManager
            }
            let existingSingletonInstance = self.singletons[String(describing: HooksManager.self)] as? HooksManager
            let instance = existingSingletonInstance ?? _get_hooksManager()
            self.singletons[String(describing: HooksManager.self)] = instance
            return instance
        }
    }

    private func _get_hooksManager() -> HooksManager {
        CioHooksManager()
    }

    // ProfileStore
    var profileStore: ProfileStore {
        if let overridenDep = overrides[String(describing: ProfileStore.self)] {
            return overridenDep as! ProfileStore
        }
        return newProfileStore
    }

    private var newProfileStore: ProfileStore {
        CioProfileStore(keyValueStorage: keyValueStorage)
    }

    // Queue
    var queue: Queue {
        if let overridenDep = overrides[String(describing: Queue.self)] {
            return overridenDep as! Queue
        }
        return newQueue
    }

    private var newQueue: Queue {
        CioQueue(siteId: siteId, storage: queueStorage, runRequest: queueRunRequest, jsonAdapter: jsonAdapter,
                 logger: logger, sdkConfigStore: sdkConfigStore, queueTimer: singleScheduleTimer, dateUtil: dateUtil)
    }

    // QueueQueryRunner
    internal var queueQueryRunner: QueueQueryRunner {
        if let overridenDep = overrides[String(describing: QueueQueryRunner.self)] {
            return overridenDep as! QueueQueryRunner
        }
        return newQueueQueryRunner
    }

    private var newQueueQueryRunner: QueueQueryRunner {
        CioQueueQueryRunner(logger: logger)
    }

    // QueueRequestManager (singleton)
    var queueRequestManager: QueueRequestManager {
        if let overridenDep = overrides[String(describing: QueueRequestManager.self)] {
            return overridenDep as! QueueRequestManager
        }
        return sharedQueueRequestManager
    }

    var sharedQueueRequestManager: QueueRequestManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_QueueRequestManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: QueueRequestManager.self)] {
                return overridenDep as! QueueRequestManager
            }
            let existingSingletonInstance = self
                .singletons[String(describing: QueueRequestManager.self)] as? QueueRequestManager
            let instance = existingSingletonInstance ?? _get_queueRequestManager()
            self.singletons[String(describing: QueueRequestManager.self)] = instance
            return instance
        }
    }

    private func _get_queueRequestManager() -> QueueRequestManager {
        CioQueueRequestManager()
    }

    // QueueRunRequest
    var queueRunRequest: QueueRunRequest {
        if let overridenDep = overrides[String(describing: QueueRunRequest.self)] {
            return overridenDep as! QueueRunRequest
        }
        return newQueueRunRequest
    }

    private var newQueueRunRequest: QueueRunRequest {
        CioQueueRunRequest(runner: queueRunner, storage: queueStorage, requestManager: queueRequestManager,
                           logger: logger, queryRunner: queueQueryRunner)
    }

    // QueueRunner
    var queueRunner: QueueRunner {
        if let overridenDep = overrides[String(describing: QueueRunner.self)] {
            return overridenDep as! QueueRunner
        }
        return newQueueRunner
    }

    private var newQueueRunner: QueueRunner {
        CioQueueRunner(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger, httpClient: httpClient,
                       hooksManager: hooksManager)
    }

    // SimpleTimer
    internal var simpleTimer: SimpleTimer {
        if let overridenDep = overrides[String(describing: SimpleTimer.self)] {
            return overridenDep as! SimpleTimer
        }
        return newSimpleTimer
    }

    private var newSimpleTimer: SimpleTimer {
        CioSimpleTimer(logger: logger)
    }

    // SingleScheduleTimer (singleton)
    internal var singleScheduleTimer: SingleScheduleTimer {
        if let overridenDep = overrides[String(describing: SingleScheduleTimer.self)] {
            return overridenDep as! SingleScheduleTimer
        }
        return sharedSingleScheduleTimer
    }

    internal var sharedSingleScheduleTimer: SingleScheduleTimer {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_SingleScheduleTimer_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: SingleScheduleTimer.self)] {
                return overridenDep as! SingleScheduleTimer
            }
            let existingSingletonInstance = self
                .singletons[String(describing: SingleScheduleTimer.self)] as? SingleScheduleTimer
            let instance = existingSingletonInstance ?? _get_singleScheduleTimer()
            self.singletons[String(describing: SingleScheduleTimer.self)] = instance
            return instance
        }
    }

    private func _get_singleScheduleTimer() -> SingleScheduleTimer {
        CioSingleScheduleTimer(timer: simpleTimer)
    }

    // ThreadUtil
    var threadUtil: ThreadUtil {
        if let overridenDep = overrides[String(describing: ThreadUtil.self)] {
            return overridenDep as! ThreadUtil
        }
        return newThreadUtil
    }

    private var newThreadUtil: ThreadUtil {
        CioThreadUtil()
    }

    // Logger
    var logger: Logger {
        if let overridenDep = overrides[String(describing: Logger.self)] {
            return overridenDep as! Logger
        }
        return newLogger
    }

    private var newLogger: Logger {
        ConsoleLogger(siteId: siteId, sdkConfigStore: sdkConfigStore)
    }

    // HttpRetryPolicy
    internal var httpRetryPolicy: HttpRetryPolicy {
        if let overridenDep = overrides[String(describing: HttpRetryPolicy.self)] {
            return overridenDep as! HttpRetryPolicy
        }
        return newHttpRetryPolicy
    }

    private var newHttpRetryPolicy: HttpRetryPolicy {
        CustomerIOAPIHttpRetryPolicy()
    }

    // FileStorage
    var fileStorage: FileStorage {
        if let overridenDep = overrides[String(describing: FileStorage.self)] {
            return overridenDep as! FileStorage
        }
        return newFileStorage
    }

    private var newFileStorage: FileStorage {
        FileManagerFileStorage(siteId: siteId, logger: logger)
    }

    // QueueStorage
    var queueStorage: QueueStorage {
        if let overridenDep = overrides[String(describing: QueueStorage.self)] {
            return overridenDep as! QueueStorage
        }
        return newQueueStorage
    }

    private var newQueueStorage: QueueStorage {
        FileManagerQueueStorage(siteId: siteId, fileStorage: fileStorage, jsonAdapter: jsonAdapter,
                                lockManager: lockManager, sdkConfigStore: sdkConfigStore, logger: logger,
                                dateUtil: dateUtil)
    }

    // ActiveWorkspacesManager (singleton)
    var activeWorkspacesManager: ActiveWorkspacesManager {
        if let overridenDep = overrides[String(describing: ActiveWorkspacesManager.self)] {
            return overridenDep as! ActiveWorkspacesManager
        }
        return sharedActiveWorkspacesManager
    }

    var sharedActiveWorkspacesManager: ActiveWorkspacesManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_ActiveWorkspacesManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: ActiveWorkspacesManager.self)] {
                return overridenDep as! ActiveWorkspacesManager
            }
            let existingSingletonInstance = self
                .singletons[String(describing: ActiveWorkspacesManager.self)] as? ActiveWorkspacesManager
            let instance = existingSingletonInstance ?? _get_activeWorkspacesManager()
            self.singletons[String(describing: ActiveWorkspacesManager.self)] = instance
            return instance
        }
    }

    private func _get_activeWorkspacesManager() -> ActiveWorkspacesManager {
        InMemoryActiveWorkspaces()
    }

    // SdkConfigStore (singleton)
    var sdkConfigStore: SdkConfigStore {
        if let overridenDep = overrides[String(describing: SdkConfigStore.self)] {
            return overridenDep as! SdkConfigStore
        }
        return sharedSdkConfigStore
    }

    var sharedSdkConfigStore: SdkConfigStore {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_SdkConfigStore_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: SdkConfigStore.self)] {
                return overridenDep as! SdkConfigStore
            }
            let existingSingletonInstance = self.singletons[String(describing: SdkConfigStore.self)] as? SdkConfigStore
            let instance = existingSingletonInstance ?? _get_sdkConfigStore()
            self.singletons[String(describing: SdkConfigStore.self)] = instance
            return instance
        }
    }

    private func _get_sdkConfigStore() -> SdkConfigStore {
        InMemorySdkConfigStore()
    }

    // JsonAdapter
    var jsonAdapter: JsonAdapter {
        if let overridenDep = overrides[String(describing: JsonAdapter.self)] {
            return overridenDep as! JsonAdapter
        }
        return newJsonAdapter
    }

    private var newJsonAdapter: JsonAdapter {
        JsonAdapter(log: logger)
    }

    // LockManager (singleton)
    var lockManager: LockManager {
        if let overridenDep = overrides[String(describing: LockManager.self)] {
            return overridenDep as! LockManager
        }
        return sharedLockManager
    }

    var sharedLockManager: LockManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_LockManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: LockManager.self)] {
                return overridenDep as! LockManager
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

    // DateUtil
    var dateUtil: DateUtil {
        if let overridenDep = overrides[String(describing: DateUtil.self)] {
            return overridenDep as! DateUtil
        }
        return newDateUtil
    }

    private var newDateUtil: DateUtil {
        SdkDateUtil()
    }

    // HttpRequestRunner
    internal var httpRequestRunner: HttpRequestRunner {
        if let overridenDep = overrides[String(describing: HttpRequestRunner.self)] {
            return overridenDep as! HttpRequestRunner
        }
        return newHttpRequestRunner
    }

    private var newHttpRequestRunner: HttpRequestRunner {
        UrlRequestHttpRequestRunner()
    }

    // KeyValueStorage
    var keyValueStorage: KeyValueStorage {
        if let overridenDep = overrides[String(describing: KeyValueStorage.self)] {
            return overridenDep as! KeyValueStorage
        }
        return newKeyValueStorage
    }

    private var newKeyValueStorage: KeyValueStorage {
        UserDefaultsKeyValueStorage(siteId: siteId)
    }
}
