// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import CioTracking
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
     let wheels = DIMessagingPush.shared.offRoadWheels
     // note the name of the property is name of the class with the first letter lowercase.

     // you can also use this syntax instead:
     let wheels: OffRoadWheels = DIMessagingPush.shared.inject(.offRoadWheels)
     // although, it's not recommended because `inject()` performs a force-cast which could cause a runtime crash of your app.
 }
 ```

 5. How do I use this graph in my test suite?
 ```
 let mockOffRoadWheels = // make a mock of OffRoadWheels class
 DIMessagingPush.shared.override(.offRoadWheels, mockOffRoadWheels)
 ```

 Then, when your test function finishes, reset the graph:
 ```
 DIMessagingPush.shared.resetOverrides()
 ```

 */

/**
 enum that contains list of all dependencies in our app.
 This allows automated unit testing against our dependency graph + ability to override nodes in graph.
 */
public enum DependencyMessagingPush: CaseIterable {
    case moduleHookProvider
    case queueRunnerHook
}

/**
 Dependency injection graph specifically with dependencies in the MessagingPush module.

 We must use 1+ different graphs because of the hierarchy of modules in this SDK.
 Example: You can't add classes from `Tracking` module in `Common`'s DI graph. However, classes
 in `Common` module can be in the `Tracking` module.
 */
public class DIMessagingPush {
    private var overrides: [DependencyMessagingPush: Any] = [:]

    internal let siteId: SiteId
    internal init(siteId: String) {
        self.siteId = siteId
    }

    // Used for tests
    public convenience init() {
        self.init(siteId: "test-identifier")
    }

    class Store {
        var instances: [String: DIMessagingPush] = [:]
        func getInstance(siteId: String) -> DIMessagingPush {
            if let existingInstance = instances[siteId] {
                return existingInstance
            }
            let newInstance = DIMessagingPush(siteId: siteId)
            instances[siteId] = newInstance
            return newInstance
        }
    }

    @Atomic internal static var store = Store()
    public static func getInstance(siteId: String) -> DIMessagingPush {
        Self.store.getInstance(siteId: siteId)
    }

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIMessagingPush.shared.override(.offRoadWheels, mockOffRoadWheels)
     ```
     */
    public func override<Value: Any>(_ dep: DependencyMessagingPush, value: Value, forType type: Value.Type) {
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
    public func inject<T>(_ dep: DependencyMessagingPush) -> T {
        switch dep {
        case .moduleHookProvider: return moduleHookProvider as! T
        case .queueRunnerHook: return queueRunnerHook as! T
        }
    }

    /**
     Use the property accessors below to inject pre-typed dependencies.
     */

    // ModuleHookProvider
    internal var moduleHookProvider: ModuleHookProvider {
        if let overridenDep = overrides[.moduleHookProvider] {
            return overridenDep as! ModuleHookProvider
        }
        return newModuleHookProvider
    }

    private var newModuleHookProvider: ModuleHookProvider {
        MessagingPushModuleHookProvider(siteId: siteId)
    }

    // QueueRunnerHook
    public var queueRunnerHook: QueueRunnerHook {
        if let overridenDep = overrides[.queueRunnerHook] {
            return overridenDep as! QueueRunnerHook
        }
        return newQueueRunnerHook
    }

    private var newQueueRunnerHook: QueueRunnerHook {
        MessagingPushQueueRunner(siteId: siteId, diTracking: dITracking)
    }
}
