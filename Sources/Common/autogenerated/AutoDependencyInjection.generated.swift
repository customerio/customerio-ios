// Generated using Sourcery 2.0.2 — https://github.com/krzysztofzablocki/Sourcery
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
    internal func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = self.deviceInfo
        countDependenciesResolved += 1

        _ = self.httpClient
        countDependenciesResolved += 1

        _ = self.globalDataStore
        countDependenciesResolved += 1

        _ = self.hooksManager
        countDependenciesResolved += 1

        _ = self.profileStore
        countDependenciesResolved += 1

        _ = self.queue
        countDependenciesResolved += 1

        _ = self.queueQueryRunner
        countDependenciesResolved += 1

        _ = self.queueRequestManager
        countDependenciesResolved += 1

        _ = self.queueRunRequest
        countDependenciesResolved += 1

        _ = self.queueRunner
        countDependenciesResolved += 1

        _ = self.simpleTimer
        countDependenciesResolved += 1

        _ = self.singleScheduleTimer
        countDependenciesResolved += 1

        _ = self.threadUtil
        countDependenciesResolved += 1

        _ = self.logger
        countDependenciesResolved += 1

        _ = self.httpRetryPolicy
        countDependenciesResolved += 1

        _ = self.deviceMetricsGrabber
        countDependenciesResolved += 1

        _ = self.fileStorage
        countDependenciesResolved += 1

        _ = self.queueStorage
        countDependenciesResolved += 1

        _ = self.jsonAdapter
        countDependenciesResolved += 1

        _ = self.lockManager
        countDependenciesResolved += 1

        _ = self.dateUtil
        countDependenciesResolved += 1

        _ = self.uIKitWrapper
        countDependenciesResolved += 1

        _ = self.httpRequestRunner
        countDependenciesResolved += 1

        _ = self.userAgentUtil
        countDependenciesResolved += 1

        _ = self.keyValueStorage
        countDependenciesResolved += 1

        return countDependenciesResolved    
    }

    // DeviceInfo
    public var deviceInfo: DeviceInfo {  
        return getOverrideInstance() ?? 
            self.newDeviceInfo
    }
    private var newDeviceInfo: DeviceInfo {    
        return CIODeviceInfo()
    }
    // HttpClient
    public var httpClient: HttpClient {  
        return getOverrideInstance() ?? 
            self.newHttpClient
    }
    private var newHttpClient: HttpClient {    
        return CIOHttpClient(siteId: self.siteId, apiKey: self.apiKey, sdkConfig: self.sdkConfig, jsonAdapter: self.jsonAdapter, httpRequestRunner: self.httpRequestRunner, globalDataStore: self.globalDataStore, logger: self.logger, timer: self.simpleTimer, retryPolicy: self.httpRetryPolicy, userAgentUtil: self.userAgentUtil)
    }
    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {  
        return getOverrideInstance() ?? 
            self.newGlobalDataStore
    }
    private var newGlobalDataStore: GlobalDataStore {    
        return CioGlobalDataStore(keyValueStorage: self.globalKeyValueStorage)
    }
    // HooksManager (singleton)
    public var hooksManager: HooksManager {  
        return getOverrideInstance() ?? 
            self.sharedHooksManager
    }
    public var sharedHooksManager: HooksManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_HooksManager_singleton_access").sync {
            if let overridenDep: HooksManager = getOverrideInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: HooksManager.self)] as? HooksManager
            let instance = existingSingletonInstance ?? _get_hooksManager()
            self.singletons[String(describing: HooksManager.self)] = instance
            return instance    
        }
    }
    private func _get_hooksManager() -> HooksManager {
        return CioHooksManager()
    }
    // ProfileStore
    public var profileStore: ProfileStore {  
        return getOverrideInstance() ?? 
            self.newProfileStore
    }
    private var newProfileStore: ProfileStore {    
        return CioProfileStore(keyValueStorage: self.keyValueStorage)
    }
    // Queue
    public var queue: Queue {  
        return getOverrideInstance() ?? 
            self.newQueue
    }
    private var newQueue: Queue {    
        return CioQueue(siteId: self.siteId, storage: self.queueStorage, runRequest: self.queueRunRequest, jsonAdapter: self.jsonAdapter, logger: self.logger, sdkConfig: self.sdkConfig, queueTimer: self.singleScheduleTimer, dateUtil: self.dateUtil)
    }
    // QueueQueryRunner
    internal var queueQueryRunner: QueueQueryRunner {  
        return getOverrideInstance() ?? 
            self.newQueueQueryRunner
    }
    private var newQueueQueryRunner: QueueQueryRunner {    
        return CioQueueQueryRunner(logger: self.logger)
    }
    // QueueRequestManager (singleton)
    public var queueRequestManager: QueueRequestManager {  
        return getOverrideInstance() ?? 
            self.sharedQueueRequestManager
    }
    public var sharedQueueRequestManager: QueueRequestManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_QueueRequestManager_singleton_access").sync {
            if let overridenDep: QueueRequestManager = getOverrideInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: QueueRequestManager.self)] as? QueueRequestManager
            let instance = existingSingletonInstance ?? _get_queueRequestManager()
            self.singletons[String(describing: QueueRequestManager.self)] = instance
            return instance    
        }
    }
    private func _get_queueRequestManager() -> QueueRequestManager {
        return CioQueueRequestManager()
    }
    // QueueRunRequest
    public var queueRunRequest: QueueRunRequest {  
        return getOverrideInstance() ?? 
            self.newQueueRunRequest
    }
    private var newQueueRunRequest: QueueRunRequest {    
        return CioQueueRunRequest(runner: self.queueRunner, storage: self.queueStorage, requestManager: self.queueRequestManager, logger: self.logger, queryRunner: self.queueQueryRunner, threadUtil: self.threadUtil)
    }
    // QueueRunner
    public var queueRunner: QueueRunner {  
        return getOverrideInstance() ?? 
            self.newQueueRunner
    }
    private var newQueueRunner: QueueRunner {    
        return CioQueueRunner(siteId: self.siteId, jsonAdapter: self.jsonAdapter, logger: self.logger, httpClient: self.httpClient, hooksManager: self.hooksManager, sdkConfig: self.sdkConfig)
    }
    // SimpleTimer
    internal var simpleTimer: SimpleTimer {  
        return getOverrideInstance() ?? 
            self.newSimpleTimer
    }
    private var newSimpleTimer: SimpleTimer {    
        return CioSimpleTimer(logger: self.logger)
    }
    // SingleScheduleTimer (singleton)
    internal var singleScheduleTimer: SingleScheduleTimer {  
        return getOverrideInstance() ?? 
            self.sharedSingleScheduleTimer
    }
    internal var sharedSingleScheduleTimer: SingleScheduleTimer {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_SingleScheduleTimer_singleton_access").sync {
            if let overridenDep: SingleScheduleTimer = getOverrideInstance() {
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
        return getOverrideInstance() ?? 
            self.newThreadUtil
    }
    private var newThreadUtil: ThreadUtil {    
        return CioThreadUtil()
    }
    // Logger
    public var logger: Logger {  
        return getOverrideInstance() ?? 
            self.newLogger
    }
    private var newLogger: Logger {    
        return ConsoleLogger(siteId: self.siteId, sdkConfig: self.sdkConfig)
    }
    // HttpRetryPolicy
    internal var httpRetryPolicy: HttpRetryPolicy {  
        return getOverrideInstance() ?? 
            self.newHttpRetryPolicy
    }
    private var newHttpRetryPolicy: HttpRetryPolicy {    
        return CustomerIOAPIHttpRetryPolicy()
    }
    // DeviceMetricsGrabber
    internal var deviceMetricsGrabber: DeviceMetricsGrabber {  
        return getOverrideInstance() ?? 
            self.newDeviceMetricsGrabber
    }
    private var newDeviceMetricsGrabber: DeviceMetricsGrabber {    
        return DeviceMetricsGrabberImpl()
    }
    // FileStorage
    public var fileStorage: FileStorage {  
        return getOverrideInstance() ?? 
            self.newFileStorage
    }
    private var newFileStorage: FileStorage {    
        return FileManagerFileStorage(siteId: self.siteId, logger: self.logger)
    }
    // QueueStorage
    public var queueStorage: QueueStorage {  
        return getOverrideInstance() ?? 
            self.newQueueStorage
    }
    private var newQueueStorage: QueueStorage {    
        return FileManagerQueueStorage(siteId: self.siteId, fileStorage: self.fileStorage, jsonAdapter: self.jsonAdapter, lockManager: self.lockManager, sdkConfig: self.sdkConfig, logger: self.logger, dateUtil: self.dateUtil)
    }
    // JsonAdapter
    public var jsonAdapter: JsonAdapter {  
        return getOverrideInstance() ?? 
            self.newJsonAdapter
    }
    private var newJsonAdapter: JsonAdapter {    
        return JsonAdapter(log: self.logger)
    }
    // LockManager (singleton)
    public var lockManager: LockManager {  
        return getOverrideInstance() ?? 
            self.sharedLockManager
    }
    public var sharedLockManager: LockManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_LockManager_singleton_access").sync {
            if let overridenDep: LockManager = getOverrideInstance() {
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
    // DateUtil
    public var dateUtil: DateUtil {  
        return getOverrideInstance() ?? 
            self.newDateUtil
    }
    private var newDateUtil: DateUtil {    
        return SdkDateUtil()
    }
    // UIKitWrapper
    @available(iOSApplicationExtension, unavailable)
    public var uIKitWrapper: UIKitWrapper {  
        return getOverrideInstance() ?? 
            self.newUIKitWrapper
    }
    @available(iOSApplicationExtension, unavailable)
    private var newUIKitWrapper: UIKitWrapper {    
        return UIKitWrapperImpl()
    }
    // HttpRequestRunner
    internal var httpRequestRunner: HttpRequestRunner {  
        return getOverrideInstance() ?? 
            self.newHttpRequestRunner
    }
    private var newHttpRequestRunner: HttpRequestRunner {    
        return UrlRequestHttpRequestRunner()
    }
    // UserAgentUtil
    public var userAgentUtil: UserAgentUtil {  
        return getOverrideInstance() ?? 
            self.newUserAgentUtil
    }
    private var newUserAgentUtil: UserAgentUtil {    
        return UserAgentUtilImpl(deviceInfo: self.deviceInfo, sdkConfig: self.sdkConfig)
    }
    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {  
        return getOverrideInstance() ?? 
            self.newKeyValueStorage
    }
    private var newKeyValueStorage: KeyValueStorage {    
        return UserDefaultsKeyValueStorage(siteId: self.siteId, deviceMetricsGrabber: self.deviceMetricsGrabber)
    }
}
