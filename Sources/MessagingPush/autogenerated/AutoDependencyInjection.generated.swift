// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
import CioInternalCommon

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
    internal func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = self.automaticPushClickHandling
        countDependenciesResolved += 1

        _ = self.pushEventHandler
        countDependenciesResolved += 1

        _ = self.pushClickHandler
        countDependenciesResolved += 1

        _ = self.pushEventHandlerProxy
        countDependenciesResolved += 1

        _ = self.pushHistory
        countDependenciesResolved += 1

        _ = self.richPushDeliveryTracker
        countDependenciesResolved += 1

        _ = self.httpClient
        countDependenciesResolved += 1

        _ = self.userNotificationCenter
        countDependenciesResolved += 1

        _ = self.userNotificationsFrameworkAdapter
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // AutomaticPushClickHandling
    @available(iOSApplicationExtension, unavailable)
    internal var automaticPushClickHandling: AutomaticPushClickHandling {
        return getOverriddenInstance() ??
            self.newAutomaticPushClickHandling
    }
    @available(iOSApplicationExtension, unavailable)
    private var newAutomaticPushClickHandling: AutomaticPushClickHandling {
        return AutomaticPushClickHandlingImpl(notificationCenterAdapter: self.userNotificationsFrameworkAdapter, logger: self.logger)
    }
    // PushEventHandler
    @available(iOSApplicationExtension, unavailable)
    internal var pushEventHandler: PushEventHandler {
        return getOverriddenInstance() ??
            self.newPushEventHandler
    }
    @available(iOSApplicationExtension, unavailable)
    private var newPushEventHandler: PushEventHandler {
        return IOSPushEventListener(jsonAdapter: self.jsonAdapter, pushEventHandlerProxy: self.pushEventHandlerProxy, moduleConfig: self.messagingPushConfigOptions, pushClickHandler: self.pushClickHandler, pushHistory: self.pushHistory, logger: self.logger)
    }
    // PushClickHandler
    @available(iOSApplicationExtension, unavailable)
    internal var pushClickHandler: PushClickHandler {
        return getOverriddenInstance() ??
            self.newPushClickHandler
    }
    @available(iOSApplicationExtension, unavailable)
    private var newPushClickHandler: PushClickHandler {
        return PushClickHandlerImpl(deepLinkUtil: self.deepLinkUtil, messagingPush: self.messagingPushInstance)
    }
    // PushEventHandlerProxy (singleton)
    @available(iOSApplicationExtension, unavailable)
    internal var pushEventHandlerProxy: PushEventHandlerProxy {
        return getOverriddenInstance() ??
            self.sharedPushEventHandlerProxy
    }
    @available(iOSApplicationExtension, unavailable)
    internal var sharedPushEventHandlerProxy: PushEventHandlerProxy {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_PushEventHandlerProxy_singleton_access").sync {
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
        return PushEventHandlerProxyImpl(logger: self.logger)
    }
    // PushHistory (singleton)
    internal var pushHistory: PushHistory {
        return getOverriddenInstance() ??
            self.sharedPushHistory
    }
    internal var sharedPushHistory: PushHistory {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_PushHistory_singleton_access").sync {
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
        return PushHistoryImpl(lockManager: self.lockManager)
    }
    // RichPushDeliveryTracker
    internal var richPushDeliveryTracker: RichPushDeliveryTracker {
        return getOverriddenInstance() ??
            self.newRichPushDeliveryTracker
    }
    private var newRichPushDeliveryTracker: RichPushDeliveryTracker {
        return RichPushDeliveryTracker(httpClient: self.httpClient, logger: self.logger)
    }
    // HttpClient
    public var httpClient: HttpClient {
        return getOverriddenInstance() ??
            self.newHttpClient
    }
    private var newHttpClient: HttpClient {
        return RichPushHttpClient(jsonAdapter: self.jsonAdapter, httpRequestRunner: self.httpRequestRunner, logger: self.logger, userAgentUtil: self.userAgentUtil)
    }
    // UserNotificationCenter
    internal var userNotificationCenter: UserNotificationCenter {
        return getOverriddenInstance() ??
            self.newUserNotificationCenter
    }
    private var newUserNotificationCenter: UserNotificationCenter {
        return UserNotificationCenterImpl()
    }
    // UserNotificationsFrameworkAdapter (singleton)
    @available(iOSApplicationExtension, unavailable)
    internal var userNotificationsFrameworkAdapter: UserNotificationsFrameworkAdapter {
        return getOverriddenInstance() ??
            self.sharedUserNotificationsFrameworkAdapter
    }
    @available(iOSApplicationExtension, unavailable)
    internal var sharedUserNotificationsFrameworkAdapter: UserNotificationsFrameworkAdapter {
        // Use a DispatchQueue to make singleton thread safe. You must create unique dispatchqueues instead of using 1 shared one or you will get a crash when trying
        // to call DispatchQueue.sync{} while already inside another DispatchQueue.sync{} call.
        return DispatchQueue(label: "DIGraphShared_UserNotificationsFrameworkAdapter_singleton_access").sync {
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
        return UserNotificationsFrameworkAdapterImpl(pushEventHandler: self.pushEventHandler, userNotificationCenter: self.userNotificationCenter, notificationCenterDelegateProxy: self.pushEventHandlerProxy)
    }
}

// swiftlint:enable all
