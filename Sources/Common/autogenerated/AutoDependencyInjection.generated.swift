// Generated using Sourcery 1.9.2 — https://github.com/krzysztofzablocki/Sourcery
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
    internal func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = deviceInfo
        countDependenciesResolved += 1

        _ = httpClient
        countDependenciesResolved += 1

        _ = globalDataStore
        countDependenciesResolved += 1

        _ = hooksManager
        countDependenciesResolved += 1

        _ = profileStore
        countDependenciesResolved += 1

        _ = queue
        countDependenciesResolved += 1

        _ = queueQueryRunner
        countDependenciesResolved += 1

        _ = queueRequestManager
        countDependenciesResolved += 1

        _ = queueRunRequest
        countDependenciesResolved += 1

        _ = queueRunner
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

        _ = dateUtil
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
        if let overridenDep = overrides[String(describing: DeviceInfo.self)] {
            return overridenDep as! DeviceInfo
        }
        return newDeviceInfo
    }

    private var newDeviceInfo: DeviceInfo {
        CIODeviceInfo()
    }

    // HttpClient
    public var httpClient: HttpClient {
        if let overridenDep = overrides[String(describing: HttpClient.self)] {
            return overridenDep as! HttpClient
        }
        return newHttpClient
    }

    private var newHttpClient: HttpClient {
        CIOHttpClient(siteId: siteId, apiKey: apiKey, sdkConfig: sdkConfig, jsonAdapter: jsonAdapter, httpRequestRunner: httpRequestRunner, globalDataStore: globalDataStore, logger: logger, timer: simpleTimer, retryPolicy: httpRetryPolicy, userAgentUtil: userAgentUtil)
    }

    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {
        if let overridenDep = overrides[String(describing: GlobalDataStore.self)] {
            return overridenDep as! GlobalDataStore
        }
        return newGlobalDataStore
    }

    private var newGlobalDataStore: GlobalDataStore {
        CioGlobalDataStore(keyValueStorage: keyValueStorage)
    }

    // HooksManager (singleton)
    public var hooksManager: HooksManager {
        if let overridenDep = overrides[String(describing: HooksManager.self)] {
            return overridenDep as! HooksManager
        }
        return sharedHooksManager
    }

    public var sharedHooksManager: HooksManager {
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
    public var profileStore: ProfileStore {
        if let overridenDep = overrides[String(describing: ProfileStore.self)] {
            return overridenDep as! ProfileStore
        }
        return newProfileStore
    }

    private var newProfileStore: ProfileStore {
        CioProfileStore(keyValueStorage: keyValueStorage)
    }

    // Queue
    public var queue: Queue {
        if let overridenDep = overrides[String(describing: Queue.self)] {
            return overridenDep as! Queue
        }
        return newQueue
    }

    private var newQueue: Queue {
        CioQueue(siteId: siteId, storage: queueStorage, runRequest: queueRunRequest, jsonAdapter: jsonAdapter, logger: logger, sdkConfig: sdkConfig, queueTimer: singleScheduleTimer, dateUtil: dateUtil)
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
    public var queueRequestManager: QueueRequestManager {
        if let overridenDep = overrides[String(describing: QueueRequestManager.self)] {
            return overridenDep as! QueueRequestManager
        }
        return sharedQueueRequestManager
    }

    public var sharedQueueRequestManager: QueueRequestManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraph_QueueRequestManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: QueueRequestManager.self)] {
                return overridenDep as! QueueRequestManager
            }
            let existingSingletonInstance = self.singletons[String(describing: QueueRequestManager.self)] as? QueueRequestManager
            let instance = existingSingletonInstance ?? _get_queueRequestManager()
            self.singletons[String(describing: QueueRequestManager.self)] = instance
            return instance
        }
    }

    private func _get_queueRequestManager() -> QueueRequestManager {
        CioQueueRequestManager()
    }

    // QueueRunRequest
    public var queueRunRequest: QueueRunRequest {
        if let overridenDep = overrides[String(describing: QueueRunRequest.self)] {
            return overridenDep as! QueueRunRequest
        }
        return newQueueRunRequest
    }

    private var newQueueRunRequest: QueueRunRequest {
        CioQueueRunRequest(runner: queueRunner, storage: queueStorage, requestManager: queueRequestManager, logger: logger, queryRunner: queueQueryRunner, threadUtil: threadUtil)
    }

    // QueueRunner
    public var queueRunner: QueueRunner {
        if let overridenDep = overrides[String(describing: QueueRunner.self)] {
            return overridenDep as! QueueRunner
        }
        return newQueueRunner
    }

    private var newQueueRunner: QueueRunner {
        CioQueueRunner(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger, httpClient: httpClient, hooksManager: hooksManager, sdkConfig: sdkConfig)
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
        if let overridenDep = overrides[String(describing: ThreadUtil.self)] {
            return overridenDep as! ThreadUtil
        }
        return newThreadUtil
    }

    private var newThreadUtil: ThreadUtil {
        CioThreadUtil()
    }

    // Logger
    public var logger: Logger {
        if let overridenDep = overrides[String(describing: Logger.self)] {
            return overridenDep as! Logger
        }
        return newLogger
    }

    private var newLogger: Logger {
        ConsoleLogger(siteId: siteId, sdkConfig: sdkConfig)
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

    // DeviceMetricsGrabber
    internal var deviceMetricsGrabber: DeviceMetricsGrabber {
        if let overridenDep = overrides[String(describing: DeviceMetricsGrabber.self)] {
            return overridenDep as! DeviceMetricsGrabber
        }
        return newDeviceMetricsGrabber
    }

    private var newDeviceMetricsGrabber: DeviceMetricsGrabber {
        DeviceMetricsGrabberImpl()
    }

    // FileStorage
    public var fileStorage: FileStorage {
        if let overridenDep = overrides[String(describing: FileStorage.self)] {
            return overridenDep as! FileStorage
        }
        return newFileStorage
    }

    private var newFileStorage: FileStorage {
        FileManagerFileStorage(siteId: siteId, logger: logger)
    }

    // QueueStorage
    public var queueStorage: QueueStorage {
        if let overridenDep = overrides[String(describing: QueueStorage.self)] {
            return overridenDep as! QueueStorage
        }
        return newQueueStorage
    }

    private var newQueueStorage: QueueStorage {
        FileManagerQueueStorage(siteId: siteId, fileStorage: fileStorage, jsonAdapter: jsonAdapter, lockManager: lockManager, sdkConfig: sdkConfig, logger: logger, dateUtil: dateUtil)
    }

    // JsonAdapter
    public var jsonAdapter: JsonAdapter {
        if let overridenDep = overrides[String(describing: JsonAdapter.self)] {
            return overridenDep as! JsonAdapter
        }
        return newJsonAdapter
    }

    private var newJsonAdapter: JsonAdapter {
        JsonAdapter(log: logger)
    }

    // LockManager (singleton)
    public var lockManager: LockManager {
        if let overridenDep = overrides[String(describing: LockManager.self)] {
            return overridenDep as! LockManager
        }
        return sharedLockManager
    }

    public var sharedLockManager: LockManager {
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
    public var dateUtil: DateUtil {
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

    // UserAgentUtil
    public var userAgentUtil: UserAgentUtil {
        if let overridenDep = overrides[String(describing: UserAgentUtil.self)] {
            return overridenDep as! UserAgentUtil
        }
        return newUserAgentUtil
    }

    private var newUserAgentUtil: UserAgentUtil {
        UserAgentUtilImpl(deviceInfo: deviceInfo, sdkConfig: sdkConfig)
    }

    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {
        if let overridenDep = overrides[String(describing: KeyValueStorage.self)] {
            return overridenDep as! KeyValueStorage
        }
        return newKeyValueStorage
    }

    private var newKeyValueStorage: KeyValueStorage {
        UserDefaultsKeyValueStorage(siteId: siteId, deviceMetricsGrabber: deviceMetricsGrabber)
    }
}
