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
    case sdkCredentialsStore
    case logger
    case jsonAdapter
    case keyValueStorage
}


/**
 Dependency injection graph specifically with dependencies in the Tracking module. 

 We must use 1+ different graphs because of the hierarchy of modules in this SDK. 
 Example: You can't add classes from `Tracking` module in `Common`'s DI graph. However, classes 
 in `Common` module can be in the `Tracking` module. 
 */
public class DITracking {
    public static var shared: DITracking = DITracking()
    private var overrides: [DependencyTracking: Any] = [:]
    private init() {
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
            case .sdkCredentialsStore: return self.sdkCredentialsStore as! T 
            case .logger: return self.logger as! T 
            case .jsonAdapter: return self.jsonAdapter as! T 
            case .keyValueStorage: return self.keyValueStorage as! T 
        }
    }

    /**
    Use the property accessors below to inject pre-typed dependencies. 
    */

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
    // KeyValueStorage
    public var keyValueStorage: KeyValueStorage {    
        if let overridenDep = self.overrides[.keyValueStorage] {
            return overridenDep as! KeyValueStorage
        }
        return self.newKeyValueStorage
    }
    private var newKeyValueStorage: KeyValueStorage {    
        return UserDefaultsKeyValueStorage()
    }
}
