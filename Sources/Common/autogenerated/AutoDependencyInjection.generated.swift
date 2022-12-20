// Generated using Sourcery 1.6.0 — https://github.com/krzysztofzablocki/Sourcery
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
    internal func testDependenciesAbleToResolve() {
        _ = self.deviceInfo    
        _ = self.httpClient    
        _ = self.sdkCredentialsStore    
        _ = self.globalDataStore    
        _ = self.hooksManager    
        _ = self.profileStore    
        _ = self.queue    
        _ = self.queueQueryRunner    
        _ = self.queueRequestManager    
        _ = self.queueRunRequest    
        _ = self.queueRunner    
        _ = self.simpleTimer    
        _ = self.singleScheduleTimer    
        _ = self.threadUtil    
        _ = self.logger    
        _ = self.httpRetryPolicy    
        _ = self.fileStorage    
        _ = self.queueStorage    
        _ = self.activeWorkspacesManager    
        _ = self.sdkConfigStore    
        _ = self.jsonAdapter    
        _ = self.lockManager    
        _ = self.dateUtil    
        _ = self.httpRequestRunner    
        _ = self.keyValueStorage    
    }

    // DeviceInfo
    public var deviceInfo: DeviceInfo {  
        if let overridenDep = self.overrides[String(describing: DeviceInfo.self)] {
            return overridenDep as! DeviceInfo
        }
        return self.newDeviceInfo
    }
    private var newDeviceInfo: DeviceInfo {    
        return CIODeviceInfo()
    }
    // HttpClient
    public var httpClient: HttpClient {  
        if let overridenDep = self.overrides[String(describing: HttpClient.self)] {
            return overridenDep as! HttpClient
        }
        return self.newHttpClient
    }
    private var newHttpClient: HttpClient {    
        return CIOHttpClient(siteId: self.siteId, sdkCredentialsStore: self.sdkCredentialsStore, configStore: self.sdkConfigStore, jsonAdapter: self.jsonAdapter, httpRequestRunner: self.httpRequestRunner, globalDataStore: self.globalDataStore, logger: self.logger, timer: self.simpleTimer, retryPolicy: self.httpRetryPolicy, deviceInfo: self.deviceInfo)
    }
    // SdkCredentialsStore
    public var sdkCredentialsStore: SdkCredentialsStore {  
        if let overridenDep = self.overrides[String(describing: SdkCredentialsStore.self)] {
            return overridenDep as! SdkCredentialsStore
        }
        return self.newSdkCredentialsStore
    }
    private var newSdkCredentialsStore: SdkCredentialsStore {    
        return CIOSdkCredentialsStore(keyValueStorage: self.keyValueStorage)
    }
    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {  
        if let overridenDep = self.overrides[String(describing: GlobalDataStore.self)] {
            return overridenDep as! GlobalDataStore
        }
        return self.newGlobalDataStore
    }
    private var newGlobalDataStore: GlobalDataStore {    
        return CioGlobalDataStore()
    }
    // HooksManager (singleton)
    public var hooksManager: HooksManager {  
        if let overridenDep = self.overrides[String(describing: HooksManager.self)] {
            return overridenDep as! HooksManager
        }
        return self.sharedHooksManager
    }
    public var sharedHooksManager: HooksManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_HooksManager_singleton_access").sync {
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
        return CioHooksManager()
    }
    // ProfileStore
    public var profileStore: ProfileStore {  
        if let overridenDep = self.overrides[String(describing: ProfileStore.self)] {
            return overridenDep as! ProfileStore
        }
        return self.newProfileStore
    }
    private var newProfileStore: ProfileStore {    
        return CioProfileStore(keyValueStorage: self.keyValueStorage)
    }
    // Queue
    public var queue: Queue {  
        if let overridenDep = self.overrides[String(describing: Queue.self)] {
            return overridenDep as! Queue
        }
        return self.newQueue
    }
    private var newQueue: Queue {    
        return CioQueue(siteId: self.siteId, storage: self.queueStorage, runRequest: self.queueRunRequest, jsonAdapter: self.jsonAdapter, logger: self.logger, sdkConfigStore: self.sdkConfigStore, queueTimer: self.singleScheduleTimer, dateUtil: self.dateUtil)
    }
    // QueueQueryRunner
    internal var queueQueryRunner: QueueQueryRunner {  
        if let overridenDep = self.overrides[String(describing: QueueQueryRunner.self)] {
            return overridenDep as! QueueQueryRunner
        }
        return self.newQueueQueryRunner
    }
    private var newQueueQueryRunner: QueueQueryRunner {    
        return CioQueueQueryRunner(logger: self.logger)
    }
    // QueueRequestManager (singleton)
    public var queueRequestManager: QueueRequestManager {  
        if let overridenDep = self.overrides[String(describing: QueueRequestManager.self)] {
            return overridenDep as! QueueRequestManager
        }
        return self.sharedQueueRequestManager
    }
    public var sharedQueueRequestManager: QueueRequestManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_QueueRequestManager_singleton_access").sync {
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
        return CioQueueRequestManager()
    }
    // QueueRunRequest
    public var queueRunRequest: QueueRunRequest {  
        if let overridenDep = self.overrides[String(describing: QueueRunRequest.self)] {
            return overridenDep as! QueueRunRequest
        }
        return self.newQueueRunRequest
    }
    private var newQueueRunRequest: QueueRunRequest {    
        return CioQueueRunRequest(runner: self.queueRunner, storage: self.queueStorage, requestManager: self.queueRequestManager, logger: self.logger, queryRunner: self.queueQueryRunner)
    }
    // QueueRunner
    public var queueRunner: QueueRunner {  
        if let overridenDep = self.overrides[String(describing: QueueRunner.self)] {
            return overridenDep as! QueueRunner
        }
        return self.newQueueRunner
    }
    private var newQueueRunner: QueueRunner {    
        return CioQueueRunner(siteId: self.siteId, jsonAdapter: self.jsonAdapter, logger: self.logger, httpClient: self.httpClient, hooksManager: self.hooksManager)
    }
    // SimpleTimer
    internal var simpleTimer: SimpleTimer {  
        if let overridenDep = self.overrides[String(describing: SimpleTimer.self)] {
            return overridenDep as! SimpleTimer
        }
        return self.newSimpleTimer
    }
    private var newSimpleTimer: SimpleTimer {    
        return CioSimpleTimer(logger: self.logger)
    }
    // SingleScheduleTimer (singleton)
    internal var singleScheduleTimer: SingleScheduleTimer {  
        if let overridenDep = self.overrides[String(describing: SingleScheduleTimer.self)] {
            return overridenDep as! SingleScheduleTimer
        }
        return self.sharedSingleScheduleTimer
    }
    internal var sharedSingleScheduleTimer: SingleScheduleTimer {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_SingleScheduleTimer_singleton_access").sync {
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
        return CioSingleScheduleTimer(timer: self.simpleTimer)
    }
    // ThreadUtil
    public var threadUtil: ThreadUtil {  
        if let overridenDep = self.overrides[String(describing: ThreadUtil.self)] {
            return overridenDep as! ThreadUtil
        }
        return self.newThreadUtil
    }
    private var newThreadUtil: ThreadUtil {    
        return CioThreadUtil()
    }
    // Logger
    public var logger: Logger {  
        if let overridenDep = self.overrides[String(describing: Logger.self)] {
            return overridenDep as! Logger
        }
        return self.newLogger
    }
    private var newLogger: Logger {    
        return ConsoleLogger(siteId: self.siteId, sdkConfigStore: self.sdkConfigStore)
    }
    // HttpRetryPolicy
    internal var httpRetryPolicy: HttpRetryPolicy {  
        if let overridenDep = self.overrides[String(describing: HttpRetryPolicy.self)] {
            return overridenDep as! HttpRetryPolicy
        }
        return self.newHttpRetryPolicy
    }
    private var newHttpRetryPolicy: HttpRetryPolicy {    
        return CustomerIOAPIHttpRetryPolicy()
    }
    // FileStorage
    public var fileStorage: FileStorage {  
        if let overridenDep = self.overrides[String(describing: FileStorage.self)] {
            return overridenDep as! FileStorage
        }
        return self.newFileStorage
    }
    private var newFileStorage: FileStorage {    
        return FileManagerFileStorage(siteId: self.siteId, logger: self.logger)
    }
    // QueueStorage
    public var queueStorage: QueueStorage {  
        if let overridenDep = self.overrides[String(describing: QueueStorage.self)] {
            return overridenDep as! QueueStorage
        }
        return self.newQueueStorage
    }
    private var newQueueStorage: QueueStorage {    
        return FileManagerQueueStorage(siteId: self.siteId, fileStorage: self.fileStorage, jsonAdapter: self.jsonAdapter, lockManager: self.lockManager, sdkConfigStore: self.sdkConfigStore, logger: self.logger, dateUtil: self.dateUtil)
    }
    // ActiveWorkspacesManager (singleton)
    public var activeWorkspacesManager: ActiveWorkspacesManager {  
        if let overridenDep = self.overrides[String(describing: ActiveWorkspacesManager.self)] {
            return overridenDep as! ActiveWorkspacesManager
        }
        return self.sharedActiveWorkspacesManager
    }
    public var sharedActiveWorkspacesManager: ActiveWorkspacesManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_ActiveWorkspacesManager_singleton_access").sync {
            if let overridenDep = self.overrides[String(describing: ActiveWorkspacesManager.self)] {
                return overridenDep as! ActiveWorkspacesManager
            }
            let existingSingletonInstance = self.singletons[String(describing: ActiveWorkspacesManager.self)] as? ActiveWorkspacesManager
            let instance = existingSingletonInstance ?? _get_activeWorkspacesManager()
            self.singletons[String(describing: ActiveWorkspacesManager.self)] = instance
            return instance    
        }
    }
    private func _get_activeWorkspacesManager() -> ActiveWorkspacesManager {
        return InMemoryActiveWorkspaces()
    }
    // SdkConfigStore (singleton)
    public var sdkConfigStore: SdkConfigStore {  
        if let overridenDep = self.overrides[String(describing: SdkConfigStore.self)] {
            return overridenDep as! SdkConfigStore
        }
        return self.sharedSdkConfigStore
    }
    public var sharedSdkConfigStore: SdkConfigStore {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_SdkConfigStore_singleton_access").sync {
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
        return InMemorySdkConfigStore()
    }
    // JsonAdapter
    public var jsonAdapter: JsonAdapter {  
        if let overridenDep = self.overrides[String(describing: JsonAdapter.self)] {
            return overridenDep as! JsonAdapter
        }
        return self.newJsonAdapter
    }
    private var newJsonAdapter: JsonAdapter {    
        return JsonAdapter(log: self.logger)
    }
    // LockManager (singleton)
    public var lockManager: LockManager {  
        if let overridenDep = self.overrides[String(describing: LockManager.self)] {
            return overridenDep as! LockManager
        }
        return self.sharedLockManager
    }
    public var sharedLockManager: LockManager {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying 
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call. 
        return DispatchQueue(label: "DIGraph_LockManager_singleton_access").sync {
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
        return LockManager()
    }
    // DateUtil
    public var dateUtil: DateUtil {  
        if let overridenDep = self.overrides[String(describing: DateUtil.self)] {
            return overridenDep as! DateUtil
        }
        return self.newDateUtil
    }
    private var newDateUtil: DateUtil {    
        return SdkDateUtil()
    }
    // HttpRequestRunner
    internal var httpRequestRunner: HttpRequestRunner {  
        if let overridenDep = self.overrides[String(describing: HttpRequestRunner.self)] {
            return overridenDep as! HttpRequestRunner
        }
        return self.newHttpRequestRunner
    }
    private var newHttpRequestRunner: HttpRequestRunner {    
        return UrlRequestHttpRequestRunner()
    }
    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {  
        if let overridenDep = self.overrides[String(describing: KeyValueStorage.self)] {
            return overridenDep as! KeyValueStorage
        }
        return self.newKeyValueStorage
    }
    private var newKeyValueStorage: KeyValueStorage {    
        return UserDefaultsKeyValueStorage(siteId: self.siteId)
    }
}
