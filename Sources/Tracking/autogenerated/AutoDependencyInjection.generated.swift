// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation

// File generated from Sourcery-DI project: https://github.com/levibostian/Sourcery-DI
// Template version 1.0.0

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
    let wheels = DITracking.shared.offRoadWheels
    // note the name of the property is name of the class with the first letter lowercase. 

    // you can also use this syntax instead:
    let wheels: OffRoadWheels = DITracking.shared.inject(.offRoadWheels)
    // although, it's not recommended because `inject()` performs a force-cast which could cause a runtime crash of your app. 
}
```

5. How do I use this graph in my test suite? 
```
let mockOffRoadWheels = // make a mock of OffRoadWheels class 
DITracking.shared.override(.offRoadWheels, mockOffRoadWheels) 
```

Then, when your test function finishes, reset the graph:
```
DITracking.shared.resetOverrides()
```

*/

/** 
 enum that contains list of all dependencies in our app. 
 This allows automated unit testing against our dependency graph + ability to override nodes in graph. 
 */
public enum DependencyTracking: CaseIterable {
    case httpClient
    case sdkCredentialsStore
    case globalDataStore
    case hooksManager
    case profileStore
    case queue
    case queueQueryRunner
    case queueRequestManager
    case queueRunRequest
    case queueRunner
    case simpleTimer
    case singleScheduleTimer
    case logger
    case httpRetryPolicy
    case fileStorage
    case queueStorage
    case activeWorkspacesManager
    case sdkConfigStore
    case jsonAdapter
    case lockManager
    case httpRequestRunner
    case keyValueStorage
}


/**
 Dependency injection graph specifically with dependencies in the Tracking module. 

 We must use 1+ different graphs because of the hierarchy of modules in this SDK. 
 Example: You can't add classes from `Tracking` module in `Common`'s DI graph. However, classes 
 in `Common` module can be in the `Tracking` module. 
 */
public class DITracking {    
    private var overrides: [DependencyTracking: Any] = [:]

    internal let siteId: SiteId
    internal init(siteId: String) {
        self.siteId = siteId
    }

    // Used for tests 
    public convenience init() {
        self.init(siteId: "test-identifier")
    }
    class Store {
        var instances: [String: DITracking] = [:]
        func getInstance(siteId: String) -> DITracking {
            if let existingInstance = self.instances[siteId] {
                return existingInstance
            }
            let newInstance = DITracking(siteId: siteId)
            self.instances[siteId] = newInstance
            return newInstance
        }
    }
    @Atomic internal static var store = Store()
    public static func getInstance(siteId: String) -> DITracking {
        Self.store.getInstance(siteId: siteId)
    }

    public static func getAllWorkspacesSharedInstance() -> DITracking {
        Self.store.getInstance(siteId: "shared")
    }

    /**
    Designed to be used only in test classes to override dependencies. 

    ```
    let mockOffRoadWheels = // make a mock of OffRoadWheels class 
    DITracking.shared.override(.offRoadWheels, mockOffRoadWheels) 
    ```
    */
    public func override<Value: Any>(_ dep: DependencyTracking, value: Value, forType type: Value.Type) {
        overrides[dep] = value 
    }

    /**
    Reset overrides. Meant to be used in `tearDown()` of tests. 
    */
    public func resetOverrides() {        
        overrides = [:]
    }

    /**
    Use this generic method of getting a dependency, if you wish. 
    */
    public func inject<T>(_ dep: DependencyTracking) -> T {                            
        switch dep {
            case .httpClient: return self.httpClient as! T 
            case .sdkCredentialsStore: return self.sdkCredentialsStore as! T 
            case .globalDataStore: return self.globalDataStore as! T 
            case .hooksManager: return self.hooksManager as! T 
            case .profileStore: return self.profileStore as! T 
            case .queue: return self.queue as! T 
            case .queueQueryRunner: return self.queueQueryRunner as! T 
            case .queueRequestManager: return self.queueRequestManager as! T 
            case .queueRunRequest: return self.queueRunRequest as! T 
            case .queueRunner: return self.queueRunner as! T 
            case .simpleTimer: return self.simpleTimer as! T 
            case .singleScheduleTimer: return self.singleScheduleTimer as! T 
            case .logger: return self.logger as! T 
            case .httpRetryPolicy: return self.httpRetryPolicy as! T 
            case .fileStorage: return self.fileStorage as! T 
            case .queueStorage: return self.queueStorage as! T 
            case .activeWorkspacesManager: return self.activeWorkspacesManager as! T 
            case .sdkConfigStore: return self.sdkConfigStore as! T 
            case .jsonAdapter: return self.jsonAdapter as! T 
            case .lockManager: return self.lockManager as! T 
            case .httpRequestRunner: return self.httpRequestRunner as! T 
            case .keyValueStorage: return self.keyValueStorage as! T 
        }
    }

    /**
    Use the property accessors below to inject pre-typed dependencies. 
    */

    // HttpClient
    public var httpClient: HttpClient {  
        if let overridenDep = self.overrides[.httpClient] {
            return overridenDep as! HttpClient
        }
        return self.newHttpClient
    }
    private var newHttpClient: HttpClient {    
        return CIOHttpClient(siteId: self.siteId, sdkCredentialsStore: self.sdkCredentialsStore, configStore: self.sdkConfigStore, jsonAdapter: self.jsonAdapter, httpRequestRunner: self.httpRequestRunner, globalDataStore: self.globalDataStore, logger: self.logger, timer: self.simpleTimer, retryPolicy: self.httpRetryPolicy)
    }
    // SdkCredentialsStore
    internal var sdkCredentialsStore: SdkCredentialsStore {  
        if let overridenDep = self.overrides[.sdkCredentialsStore] {
            return overridenDep as! SdkCredentialsStore
        }
        return self.newSdkCredentialsStore
    }
    private var newSdkCredentialsStore: SdkCredentialsStore {    
        return CIOSdkCredentialsStore(keyValueStorage: self.keyValueStorage)
    }
    // GlobalDataStore
    public var globalDataStore: GlobalDataStore {  
        if let overridenDep = self.overrides[.globalDataStore] {
            return overridenDep as! GlobalDataStore
        }
        return self.newGlobalDataStore
    }
    private var newGlobalDataStore: GlobalDataStore {    
        return CioGlobalDataStore()
    }
    // HooksManager (singleton)
    public var hooksManager: HooksManager {  
        if let overridenDep = self.overrides[.hooksManager] {
            return overridenDep as! HooksManager
        }
        return self.sharedHooksManager
    }
    private let _hooksManager_queue = DispatchQueue(label: "DI_get_hooksManager_queue")
    private var _hooksManager_shared: HooksManager?
    public var sharedHooksManager: HooksManager {
        return _hooksManager_queue.sync {
            if let overridenDep = self.overrides[.hooksManager] {
                return overridenDep as! HooksManager
            }
            let res = _hooksManager_shared ?? _get_hooksManager()
            _hooksManager_shared = res
            return res
        }
    }
    private func _get_hooksManager() -> HooksManager {
        return CioHooksManager()
    }
    // ProfileStore
    public var profileStore: ProfileStore {  
        if let overridenDep = self.overrides[.profileStore] {
            return overridenDep as! ProfileStore
        }
        return self.newProfileStore
    }
    private var newProfileStore: ProfileStore {    
        return CioProfileStore(keyValueStorage: self.keyValueStorage)
    }
    // Queue
    public var queue: Queue {  
        if let overridenDep = self.overrides[.queue] {
            return overridenDep as! Queue
        }
        return self.newQueue
    }
    private var newQueue: Queue {    
        return CioQueue(siteId: self.siteId, storage: self.queueStorage, runRequest: self.queueRunRequest, jsonAdapter: self.jsonAdapter, logger: self.logger, sdkConfigStore: self.sdkConfigStore, queueTimer: self.singleScheduleTimer)
    }
    // QueueQueryRunner
    internal var queueQueryRunner: QueueQueryRunner {  
        if let overridenDep = self.overrides[.queueQueryRunner] {
            return overridenDep as! QueueQueryRunner
        }
        return self.newQueueQueryRunner
    }
    private var newQueueQueryRunner: QueueQueryRunner {    
        return CioQueueQueryRunner()
    }
    // QueueRequestManager (singleton)
    public var queueRequestManager: QueueRequestManager {  
        if let overridenDep = self.overrides[.queueRequestManager] {
            return overridenDep as! QueueRequestManager
        }
        return self.sharedQueueRequestManager
    }
    private let _queueRequestManager_queue = DispatchQueue(label: "DI_get_queueRequestManager_queue")
    private var _queueRequestManager_shared: QueueRequestManager?
    public var sharedQueueRequestManager: QueueRequestManager {
        return _queueRequestManager_queue.sync {
            if let overridenDep = self.overrides[.queueRequestManager] {
                return overridenDep as! QueueRequestManager
            }
            let res = _queueRequestManager_shared ?? _get_queueRequestManager()
            _queueRequestManager_shared = res
            return res
        }
    }
    private func _get_queueRequestManager() -> QueueRequestManager {
        return CioQueueRequestManager()
    }
    // QueueRunRequest
    public var queueRunRequest: QueueRunRequest {  
        if let overridenDep = self.overrides[.queueRunRequest] {
            return overridenDep as! QueueRunRequest
        }
        return self.newQueueRunRequest
    }
    private var newQueueRunRequest: QueueRunRequest {    
        return CioQueueRunRequest(runner: self.queueRunner, storage: self.queueStorage, requestManager: self.queueRequestManager, logger: self.logger, queryRunner: self.queueQueryRunner)
    }
    // QueueRunner
    public var queueRunner: QueueRunner {  
        if let overridenDep = self.overrides[.queueRunner] {
            return overridenDep as! QueueRunner
        }
        return self.newQueueRunner
    }
    private var newQueueRunner: QueueRunner {    
        return CioQueueRunner(siteId: self.siteId, jsonAdapter: self.jsonAdapter, logger: self.logger, httpClient: self.httpClient, hooksManager: self.hooksManager)
    }
    // SimpleTimer
    internal var simpleTimer: SimpleTimer {  
        if let overridenDep = self.overrides[.simpleTimer] {
            return overridenDep as! SimpleTimer
        }
        return self.newSimpleTimer
    }
    private var newSimpleTimer: SimpleTimer {    
        return CioSimpleTimer(logger: self.logger)
    }
    // SingleScheduleTimer (singleton)
    internal var singleScheduleTimer: SingleScheduleTimer {  
        if let overridenDep = self.overrides[.singleScheduleTimer] {
            return overridenDep as! SingleScheduleTimer
        }
        return self.sharedSingleScheduleTimer
    }
    private let _singleScheduleTimer_queue = DispatchQueue(label: "DI_get_singleScheduleTimer_queue")
    private var _singleScheduleTimer_shared: SingleScheduleTimer?
    internal var sharedSingleScheduleTimer: SingleScheduleTimer {
        return _singleScheduleTimer_queue.sync {
            if let overridenDep = self.overrides[.singleScheduleTimer] {
                return overridenDep as! SingleScheduleTimer
            }
            let res = _singleScheduleTimer_shared ?? _get_singleScheduleTimer()
            _singleScheduleTimer_shared = res
            return res
        }
    }
    private func _get_singleScheduleTimer() -> SingleScheduleTimer {
        return CioSingleScheduleTimer(timer: self.simpleTimer)
    }
    // Logger
    public var logger: Logger {  
        if let overridenDep = self.overrides[.logger] {
            return overridenDep as! Logger
        }
        return self.newLogger
    }
    private var newLogger: Logger {    
        return ConsoleLogger(siteId: self.siteId, sdkConfigStore: self.sdkConfigStore)
    }
    // HttpRetryPolicy
    internal var httpRetryPolicy: HttpRetryPolicy {  
        if let overridenDep = self.overrides[.httpRetryPolicy] {
            return overridenDep as! HttpRetryPolicy
        }
        return self.newHttpRetryPolicy
    }
    private var newHttpRetryPolicy: HttpRetryPolicy {    
        return CustomerIOAPIHttpRetryPolicy()
    }
    // FileStorage
    public var fileStorage: FileStorage {  
        if let overridenDep = self.overrides[.fileStorage] {
            return overridenDep as! FileStorage
        }
        return self.newFileStorage
    }
    private var newFileStorage: FileStorage {    
        return FileManagerFileStorage(siteId: self.siteId, logger: self.logger)
    }
    // QueueStorage
    public var queueStorage: QueueStorage {  
        if let overridenDep = self.overrides[.queueStorage] {
            return overridenDep as! QueueStorage
        }
        return self.newQueueStorage
    }
    private var newQueueStorage: QueueStorage {    
        return FileManagerQueueStorage(siteId: self.siteId, fileStorage: self.fileStorage, jsonAdapter: self.jsonAdapter, lockManager: self.lockManager)
    }
    // ActiveWorkspacesManager (singleton)
    internal var activeWorkspacesManager: ActiveWorkspacesManager {  
        if let overridenDep = self.overrides[.activeWorkspacesManager] {
            return overridenDep as! ActiveWorkspacesManager
        }
        return self.sharedActiveWorkspacesManager
    }
    private let _activeWorkspacesManager_queue = DispatchQueue(label: "DI_get_activeWorkspacesManager_queue")
    private var _activeWorkspacesManager_shared: ActiveWorkspacesManager?
    internal var sharedActiveWorkspacesManager: ActiveWorkspacesManager {
        return _activeWorkspacesManager_queue.sync {
            if let overridenDep = self.overrides[.activeWorkspacesManager] {
                return overridenDep as! ActiveWorkspacesManager
            }
            let res = _activeWorkspacesManager_shared ?? _get_activeWorkspacesManager()
            _activeWorkspacesManager_shared = res
            return res
        }
    }
    private func _get_activeWorkspacesManager() -> ActiveWorkspacesManager {
        return InMemoryActiveWorkspaces()
    }
    // SdkConfigStore (singleton)
    public var sdkConfigStore: SdkConfigStore {  
        if let overridenDep = self.overrides[.sdkConfigStore] {
            return overridenDep as! SdkConfigStore
        }
        return self.sharedSdkConfigStore
    }
    private let _sdkConfigStore_queue = DispatchQueue(label: "DI_get_sdkConfigStore_queue")
    private var _sdkConfigStore_shared: SdkConfigStore?
    public var sharedSdkConfigStore: SdkConfigStore {
        return _sdkConfigStore_queue.sync {
            if let overridenDep = self.overrides[.sdkConfigStore] {
                return overridenDep as! SdkConfigStore
            }
            let res = _sdkConfigStore_shared ?? _get_sdkConfigStore()
            _sdkConfigStore_shared = res
            return res
        }
    }
    private func _get_sdkConfigStore() -> SdkConfigStore {
        return InMemorySdkConfigStore()
    }
    // JsonAdapter
    public var jsonAdapter: JsonAdapter {  
        if let overridenDep = self.overrides[.jsonAdapter] {
            return overridenDep as! JsonAdapter
        }
        return self.newJsonAdapter
    }
    private var newJsonAdapter: JsonAdapter {    
        return JsonAdapter(log: self.logger)
    }
    // LockManager (singleton)
    public var lockManager: LockManager {  
        if let overridenDep = self.overrides[.lockManager] {
            return overridenDep as! LockManager
        }
        return self.sharedLockManager
    }
    private let _lockManager_queue = DispatchQueue(label: "DI_get_lockManager_queue")
    private var _lockManager_shared: LockManager?
    public var sharedLockManager: LockManager {
        return _lockManager_queue.sync {
            if let overridenDep = self.overrides[.lockManager] {
                return overridenDep as! LockManager
            }
            let res = _lockManager_shared ?? _get_lockManager()
            _lockManager_shared = res
            return res
        }
    }
    private func _get_lockManager() -> LockManager {
        return LockManager()
    }
    // HttpRequestRunner
    internal var httpRequestRunner: HttpRequestRunner {  
        if let overridenDep = self.overrides[.httpRequestRunner] {
            return overridenDep as! HttpRequestRunner
        }
        return self.newHttpRequestRunner
    }
    private var newHttpRequestRunner: HttpRequestRunner {    
        return UrlRequestHttpRequestRunner()
    }
    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {  
        if let overridenDep = self.overrides[.keyValueStorage] {
            return overridenDep as! KeyValueStorage
        }
        return self.newKeyValueStorage
    }
    private var newKeyValueStorage: KeyValueStorage {    
        return UserDefaultsKeyValueStorage(siteId: self.siteId)
    }
}
