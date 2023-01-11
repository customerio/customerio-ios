// Generated using Sourcery 1.9.2 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Common
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
    func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = cleanupRepository
        countDependenciesResolved += 1

        _ = deviceAttributesProvider
        countDependenciesResolved += 1

        _ = queueRunnerHook
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // CleanupRepository
    var cleanupRepository: CleanupRepository {
        if let overridenDep = overrides[String(describing: CleanupRepository.self)] {
            return overridenDep as! CleanupRepository
        }
        return newCleanupRepository
    }

    private var newCleanupRepository: CleanupRepository {
        CioCleanupRepository(queue: queue)
    }

    // DeviceAttributesProvider
    var deviceAttributesProvider: DeviceAttributesProvider {
        if let overridenDep = overrides[String(describing: DeviceAttributesProvider.self)] {
            return overridenDep as! DeviceAttributesProvider
        }
        return newDeviceAttributesProvider
    }

    private var newDeviceAttributesProvider: DeviceAttributesProvider {
        SdkDeviceAttributesProvider(sdkConfig: sdkConfig, deviceInfo: deviceInfo)
    }

    // QueueRunnerHook
    var queueRunnerHook: QueueRunnerHook {
        if let overridenDep = overrides[String(describing: QueueRunnerHook.self)] {
            return overridenDep as! QueueRunnerHook
        }
        return newQueueRunnerHook
    }

    private var newQueueRunnerHook: QueueRunnerHook {
        TrackingQueueRunner(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger, httpClient: httpClient, sdkConfig: sdkConfig)
    }
}
