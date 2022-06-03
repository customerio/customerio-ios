// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Common
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
internal enum DependencyTracking: CaseIterable {
    case cleanupRepository
    case queueRunnerHook
}

/**
 Dependency injection graph specifically with dependencies in the Tracking module.

 We must use 1+ different graphs because of the hierarchy of modules in this SDK.
 Example: You can't add classes from `Tracking` module in `Common`'s DI graph. However, classes
 in `Common` module can be in the `Tracking` module.
 */
internal class DITracking {
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
    internal func override<Value: Any>(_ dep: DependencyTracking, value: Value, forType type: Value.Type) {
        overrides[dep] = value
    }

    /**
     Reset overrides. Meant to be used in `tearDown()` of tests.
     */
    internal func resetOverrides() {
        overrides = [:]
    }

    /**
     Use this generic method of getting a dependency, if you wish.
     */
    internal func inject<T>(_ dep: DependencyTracking) -> T {
        switch dep {
        case .cleanupRepository: return cleanupRepository as! T
        case .queueRunnerHook: return queueRunnerHook as! T
        }
    }

    /**
     Use the property accessors below to inject pre-typed dependencies.
     */

    // CleanupRepository
    internal var cleanupRepository: CleanupRepository {
        if let overridenDep = overrides[.cleanupRepository] {
            return overridenDep as! CleanupRepository
        }
        return newCleanupRepository
    }

    private var newCleanupRepository: CleanupRepository {
        CioCleanupRepository(diCommon: dICommon)
    }

    // QueueRunnerHook
    internal var queueRunnerHook: QueueRunnerHook {
        if let overridenDep = overrides[.queueRunnerHook] {
            return overridenDep as! QueueRunnerHook
        }
        return newQueueRunnerHook
    }

    private var newQueueRunnerHook: QueueRunnerHook {
        TrackingQueueRunner(siteId: siteId, diGraph: dICommon)
    }
}
