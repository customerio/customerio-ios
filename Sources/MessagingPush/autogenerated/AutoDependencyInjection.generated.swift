// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import CioInternalCommon
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
     let wheels = DIGraphShared.shared.offRoadWheels
     // note the name of the property is name of the class with the first letter lowercase.
 }
 ```

 5. How do I use this graph in my test suite?
 ```
 let mockOffRoadWheels = // make a mock of OffRoadWheels class
 DIGraphShared.shared.override(mockOffRoadWheels, OffRoadWheels.self)
 ```

 Then, when your test function finishes, reset the graph:
 ```
 DIGraphShared.shared.reset()
 ```

 */

extension DIGraphShared {
    // call in automated test suite to confirm that all dependnecies able to resolve and not cause runtime exceptions.
    // internal scope so each module can provide their own version of the function with the same name.
    @available(iOSApplicationExtension, unavailable) // some properties could be unavailable to app extensions so this function must also.
    func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = automaticPushClickHandling
        countDependenciesResolved += 1

        _ = pushEventHandler
        countDependenciesResolved += 1

        _ = pushClickHandler
        countDependenciesResolved += 1

        _ = pushEventHandlerProxy
        countDependenciesResolved += 1

        _ = pushHistory
        countDependenciesResolved += 1

        _ = pushNotificationLogger
        countDependenciesResolved += 1

        _ = richPushDeliveryTracker
        countDependenciesResolved += 1

        _ = httpClient
        countDependenciesResolved += 1

        _ = userNotificationCenter
        countDependenciesResolved += 1

        _ = userNotificationsFrameworkAdapter
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // AutomaticPushClickHandling
    @available(iOSApplicationExtension, unavailable)
    var automaticPushClickHandling: AutomaticPushClickHandling {
        getOverriddenInstance() ??
            newAutomaticPushClickHandling
    }

    @available(iOSApplicationExtension, unavailable)
    private var newAutomaticPushClickHandling: AutomaticPushClickHandling {
        AutomaticPushClickHandlingImpl(notificationCenterAdapter: userNotificationsFrameworkAdapter, logger: logger)
    }

    // PushEventHandler
    @available(iOSApplicationExtension, unavailable)
    var pushEventHandler: PushEventHandler {
        getOverriddenInstance() ??
            newPushEventHandler
    }

    @available(iOSApplicationExtension, unavailable)
    private var newPushEventHandler: PushEventHandler {
        IOSPushEventListener(jsonAdapter: jsonAdapter, pushEventHandlerProxy: pushEventHandlerProxy, moduleConfig: messagingPushConfigOptions, pushClickHandler: pushClickHandler, pushHistory: pushHistory, logger: logger, pushLogger: pushNotificationLogger)
    }

    // PushClickHandler
    @available(iOSApplicationExtension, unavailable)
    var pushClickHandler: PushClickHandler {
        getOverriddenInstance() ??
            newPushClickHandler
    }

    @available(iOSApplicationExtension, unavailable)
    private var newPushClickHandler: PushClickHandler {
        PushClickHandlerImpl(deepLinkUtil: deepLinkUtil, messagingPush: messagingPushInstance, pushLogger: pushNotificationLogger, commonLogger: sdkCommonLogger)
    }

    // PushEventHandlerProxy (singleton)
    @available(iOSApplicationExtension, unavailable)
    var pushEventHandlerProxy: PushEventHandlerProxy {
        getOverriddenInstance() ??
            sharedPushEventHandlerProxy
    }

    @available(iOSApplicationExtension, unavailable)
    var sharedPushEventHandlerProxy: PushEventHandlerProxy {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_PushEventHandlerProxy_singleton_access").sync {
            if let overridenDep: PushEventHandlerProxy = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: PushEventHandlerProxy.self)] as? PushEventHandlerProxy
            let instance = existingSingletonInstance ?? _get_pushEventHandlerProxy()
            self.singletons[String(describing: PushEventHandlerProxy.self)] = instance
            return instance
        }
    }

    @available(iOSApplicationExtension, unavailable)
    private func _get_pushEventHandlerProxy() -> PushEventHandlerProxy {
        PushEventHandlerProxyImpl(logger: logger)
    }

    // PushHistory (singleton)
    var pushHistory: PushHistory {
        getOverriddenInstance() ??
            sharedPushHistory
    }

    var sharedPushHistory: PushHistory {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_PushHistory_singleton_access").sync {
            if let overridenDep: PushHistory = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: PushHistory.self)] as? PushHistory
            let instance = existingSingletonInstance ?? _get_pushHistory()
            self.singletons[String(describing: PushHistory.self)] = instance
            return instance
        }
    }

    private func _get_pushHistory() -> PushHistory {
        PushHistoryImpl(lockManager: lockManager)
    }

    // PushNotificationLogger
    var pushNotificationLogger: PushNotificationLogger {
        getOverriddenInstance() ??
            newPushNotificationLogger
    }

    private var newPushNotificationLogger: PushNotificationLogger {
        PushNotificationLoggerImpl(logger: logger)
    }

    // RichPushDeliveryTracker
    var richPushDeliveryTracker: RichPushDeliveryTracker {
        getOverriddenInstance() ??
            newRichPushDeliveryTracker
    }

    private var newRichPushDeliveryTracker: RichPushDeliveryTracker {
        RichPushDeliveryTracker(httpClient: httpClient, logger: logger)
    }

    // HttpClient
    public var httpClient: HttpClient {
        getOverriddenInstance() ??
            newHttpClient
    }

    private var newHttpClient: HttpClient {
        RichPushHttpClient(jsonAdapter: jsonAdapter, httpRequestRunner: httpRequestRunner, logger: logger, userAgentUtil: userAgentUtil)
    }

    // UserNotificationCenter
    var userNotificationCenter: UserNotificationCenter {
        getOverriddenInstance() ??
            newUserNotificationCenter
    }

    private var newUserNotificationCenter: UserNotificationCenter {
        UserNotificationCenterImpl()
    }

    // UserNotificationsFrameworkAdapter (singleton)
    @available(iOSApplicationExtension, unavailable)
    var userNotificationsFrameworkAdapter: UserNotificationsFrameworkAdapter {
        getOverriddenInstance() ??
            sharedUserNotificationsFrameworkAdapter
    }

    @available(iOSApplicationExtension, unavailable)
    var sharedUserNotificationsFrameworkAdapter: UserNotificationsFrameworkAdapter {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        DispatchQueue(label: "DIGraphShared_UserNotificationsFrameworkAdapter_singleton_access").sync {
            if let overridenDep: UserNotificationsFrameworkAdapter = getOverriddenInstance() {
                return overridenDep
            }
            let existingSingletonInstance = self.singletons[String(describing: UserNotificationsFrameworkAdapter.self)] as? UserNotificationsFrameworkAdapter
            let instance = existingSingletonInstance ?? _get_userNotificationsFrameworkAdapter()
            self.singletons[String(describing: UserNotificationsFrameworkAdapter.self)] = instance
            return instance
        }
    }

    @available(iOSApplicationExtension, unavailable)
    private func _get_userNotificationsFrameworkAdapter() -> UserNotificationsFrameworkAdapter {
        UserNotificationsFrameworkAdapterImpl(pushEventHandler: pushEventHandler, userNotificationCenter: userNotificationCenter, notificationCenterDelegateProxy: pushEventHandlerProxy)
    }
}

// swiftlint:enable all
