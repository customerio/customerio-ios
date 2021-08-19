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

enum Dependency: CaseIterable {
    case sdkCredentialsStore
    case keyValueStorage
}

class DI {
    static var shared = DI()
    private var overrides: [Dependency: Any] = [:]
    private init() {}

    /**
     Designed to be used only for testing purposes to override dependencies.
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
        case .sdkCredentialsStore: return sdkCredentialsStore as! T
        case .keyValueStorage: return keyValueStorage as! T
        }
    }

    /**
     Use the property accessors below to inject pre-typed dependencies.
     */

    // SdkCredentialsStore
    var sdkCredentialsStore: SdkCredentialsStore {
        if let overridenDep = overrides[.sdkCredentialsStore] {
            return overridenDep as! SdkCredentialsStore
        }
        return newSdkCredentialsStore
    }

    var newSdkCredentialsStore: SdkCredentialsStore {
        CIOSdkCredentialsStore(keyValueStorage: keyValueStorage)
    }

    // KeyValueStorage
    var keyValueStorage: KeyValueStorage {
        if let overridenDep = overrides[.keyValueStorage] {
            return overridenDep as! KeyValueStorage
        }
        return newKeyValueStorage
    }

    var newKeyValueStorage: KeyValueStorage {
        UserDefaultsKeyValueStorage()
    }
}
