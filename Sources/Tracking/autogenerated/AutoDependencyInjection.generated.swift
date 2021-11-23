// Generated using Sourcery 1.6.0 — https://github.com/krzysztofzablocki/Sourcery
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
    let wheels = DI.shared.offRoadWheels
    // note the name of the property is name of the class with the first letter lowercase. 

    // you can also use this syntax instead:
    let wheels: OffRoadWheels = DI.shared.inject(.offRoadWheels)
    // although, it's not recommended because `inject()` performs a force-cast which could cause a runtime crash of your app. 
}
```

5. How do I use this graph in my test suite? 
```
let mockOffRoadWheels = // make a mock of OffRoadWheels class 
DI.shared.override(.offRoadWheels, mockOffRoadWheels) 
```

Then, when your test function finishes, reset the graph:
```
DI.shared.resetOverrides()
```

*/

/** 
 enum that contains list of all dependencies in our app. 
 This allows automated unit testing against our dependency graph + ability to override nodes in graph. 
 */
 enum Dependency: CaseIterable {
    case httpClient
    case identifyRepository
    case sdkCredentialsStore
    case globalDataStore
    case eventBus
    case profileStore
    case logger
    case sdkConfigStore
    case jsonAdapter
    case httpRequestRunner
    case keyValueStorage
}


/**
 Dependency injection graph specifically with dependencies in the  module. 

 We must use 1+ different graphs because of the hierarchy of modules in this SDK. 
 Example: You can't add classes from `Tracking` module in `Common`'s DI graph. However, classes 
 in `Common` module can be in the `Tracking` module. 
 */
 public class DI {    
    private var overrides: [Dependency: Any] = [:]

    internal let siteId: SiteId
    internal init(siteId: String) {
        self.siteId = siteId
    }

    // Used for tests 
    public convenience init() {
        self.init(siteId: "test-identifier")
    }
    class Store {
        var instances: [String: DI] = [:]
        func getInstance(siteId: String) -> DI {
            if let existingInstance = self.instances[siteId] {
                return existingInstance
            }
            let newInstance = DI(siteId: siteId)
            self.instances[siteId] = newInstance
            return newInstance
        }
    }
    @Atomic internal static var store = Store()
    public static func getInstance(siteId: String) -> DI {
        Self.store.getInstance(siteId: siteId)
    }

    /**
    Designed to be used only in test classes to override dependencies. 

    ```
    let mockOffRoadWheels = // make a mock of OffRoadWheels class 
    DI.shared.override(.offRoadWheels, mockOffRoadWheels) 
    ```
    */
     func override<Value: Any>(_ dep: Dependency, value: Value, forType type: Value.Type) {
        overrides[dep] = value 
    }

    /**
    Reset overrides. Meant to be used in `tearDown()` of tests. 
    */
     func resetOverrides() {        
        overrides = [:]
    }

    /**
    Use this generic method of getting a dependency, if you wish. 
    */
     func inject<T>(_ dep: Dependency) -> T {                            
        switch dep {
            case .httpClient: return self.httpClient as! T 
            case .identifyRepository: return self.identifyRepository as! T 
            case .sdkCredentialsStore: return self.sdkCredentialsStore as! T 
            case .globalDataStore: return self.globalDataStore as! T 
            case .eventBus: return self.eventBus as! T 
            case .profileStore: return self.profileStore as! T 
            case .logger: return self.logger as! T 
            case .sdkConfigStore: return self.sdkConfigStore as! T 
            case .jsonAdapter: return self.jsonAdapter as! T 
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
        return CIOHttpClient(siteId: self.siteId, sdkCredentialsStore: self.sdkCredentialsStore, configStore: self.sdkConfigStore, jsonAdapter: self.jsonAdapter, httpRequestRunner: self.httpRequestRunner)
    }
    // IdentifyRepository
    internal var identifyRepository: IdentifyRepository {  
        if let overridenDep = self.overrides[.identifyRepository] {
            return overridenDep as! IdentifyRepository
        }
        return self.newIdentifyRepository
    }
    private var newIdentifyRepository: IdentifyRepository {    
        return CIOIdentifyRepository(siteId: self.siteId, httpClient: self.httpClient, jsonAdapter: self.jsonAdapter, eventBus: self.eventBus, profileStore: self.profileStore)
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
    // EventBus
    public var eventBus: EventBus {  
        if let overridenDep = self.overrides[.eventBus] {
            return overridenDep as! EventBus
        }
        return self.newEventBus
    }
    private var newEventBus: EventBus {    
        return CioNotificationCenter()
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
    // Logger
    public var logger: Logger {  
        if let overridenDep = self.overrides[.logger] {
            return overridenDep as! Logger
        }
        return self.newLogger
    }
    private var newLogger: Logger {    
        return ConsoleLogger()
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
