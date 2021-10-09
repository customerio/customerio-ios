// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
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
    case identifyRepository
    case sdkCredentialsStore
    case eventBus
    case profileStore
    case logger
    case sdkConfigStore
    case jsonAdapter
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
            if let existingInstance = instances[siteId] {
                return existingInstance
            }
            let newInstance = DITracking(siteId: siteId)
            instances[siteId] = newInstance
            return newInstance
        }
    }

    @Atomic internal static var store = Store()
    public static func getInstance(siteId: String) -> DITracking {
        Self.store.getInstance(siteId: siteId)
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
        case .httpClient: return httpClient as! T
        case .identifyRepository: return identifyRepository as! T
        case .sdkCredentialsStore: return sdkCredentialsStore as! T
        case .eventBus: return eventBus as! T
        case .profileStore: return profileStore as! T
        case .logger: return logger as! T
        case .sdkConfigStore: return sdkConfigStore as! T
        case .jsonAdapter: return jsonAdapter as! T
        case .httpRequestRunner: return httpRequestRunner as! T
        case .keyValueStorage: return keyValueStorage as! T
        }
    }

    /**
     Use the property accessors below to inject pre-typed dependencies.
     */

    // HttpClient
    public var httpClient: HttpClient {
        if let overridenDep = overrides[.httpClient] {
            return overridenDep as! HttpClient
        }
        return newHttpClient
    }

    private var newHttpClient: HttpClient {
        CIOHttpClient(siteId: siteId, sdkCredentialsStore: sdkCredentialsStore, configStore: sdkConfigStore,
                      jsonAdapter: jsonAdapter, httpRequestRunner: httpRequestRunner)
    }

    // IdentifyRepository
    internal var identifyRepository: IdentifyRepository {
        if let overridenDep = overrides[.identifyRepository] {
            return overridenDep as! IdentifyRepository
        }
        return newIdentifyRepository
    }

    private var newIdentifyRepository: IdentifyRepository {
        CIOIdentifyRepository(siteId: siteId, httpClient: httpClient, jsonAdapter: jsonAdapter, eventBus: eventBus,
                              profileStore: profileStore)
    }

    // SdkCredentialsStore
    internal var sdkCredentialsStore: SdkCredentialsStore {
        if let overridenDep = overrides[.sdkCredentialsStore] {
            return overridenDep as! SdkCredentialsStore
        }
        return newSdkCredentialsStore
    }

    private var newSdkCredentialsStore: SdkCredentialsStore {
        CIOSdkCredentialsStore(keyValueStorage: keyValueStorage)
    }

    // EventBus
    public var eventBus: EventBus {
        if let overridenDep = overrides[.eventBus] {
            return overridenDep as! EventBus
        }
        return newEventBus
    }

    private var newEventBus: EventBus {
        CioNotificationCenter()
    }

    // ProfileStore
    public var profileStore: ProfileStore {
        if let overridenDep = overrides[.profileStore] {
            return overridenDep as! ProfileStore
        }
        return newProfileStore
    }

    private var newProfileStore: ProfileStore {
        CioProfileStore(keyValueStorage: keyValueStorage)
    }

    // Logger
    public var logger: Logger {
        if let overridenDep = overrides[.logger] {
            return overridenDep as! Logger
        }
        return newLogger
    }

    private var newLogger: Logger {
        ConsoleLogger()
    }

    // SdkConfigStore (singleton)
    public var sdkConfigStore: SdkConfigStore {
        if let overridenDep = overrides[.sdkConfigStore] {
            return overridenDep as! SdkConfigStore
        }
        return sharedSdkConfigStore
    }

    private let _sdkConfigStore_queue = DispatchQueue(label: "DI_get_sdkConfigStore_queue")
    private var _sdkConfigStore_shared: SdkConfigStore?
    public var sharedSdkConfigStore: SdkConfigStore {
        _sdkConfigStore_queue.sync {
            if let overridenDep = self.overrides[.sdkConfigStore] {
                return overridenDep as! SdkConfigStore
            }
            let res = _sdkConfigStore_shared ?? _get_sdkConfigStore()
            _sdkConfigStore_shared = res
            return res
        }
    }

    private func _get_sdkConfigStore() -> SdkConfigStore {
        InMemorySdkConfigStore()
    }

    // JsonAdapter
    public var jsonAdapter: JsonAdapter {
        if let overridenDep = overrides[.jsonAdapter] {
            return overridenDep as! JsonAdapter
        }
        return newJsonAdapter
    }

    private var newJsonAdapter: JsonAdapter {
        JsonAdapter(log: logger)
    }

    // HttpRequestRunner
    internal var httpRequestRunner: HttpRequestRunner {
        if let overridenDep = overrides[.httpRequestRunner] {
            return overridenDep as! HttpRequestRunner
        }
        return newHttpRequestRunner
    }

    private var newHttpRequestRunner: HttpRequestRunner {
        UrlRequestHttpRequestRunner()
    }

    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {
        if let overridenDep = overrides[.keyValueStorage] {
            return overridenDep as! KeyValueStorage
        }
        return newKeyValueStorage
    }

    private var newKeyValueStorage: KeyValueStorage {
        UserDefaultsKeyValueStorage(siteId: siteId)
    }
}
