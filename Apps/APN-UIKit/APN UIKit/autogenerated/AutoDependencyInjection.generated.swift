// Generated using Sourcery 2.2.6 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

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
    internal func testDependenciesAbleToResolve() -> Int {
        var countDependenciesResolved = 0

        _ = self.deepLinksHandlerUtil
        countDependenciesResolved += 1

        _ = self.notificationUtil
        countDependenciesResolved += 1

        _ = self.settingsService
        countDependenciesResolved += 1

        _ = self.storage
        countDependenciesResolved += 1

        _ = self.userDefaults
        countDependenciesResolved += 1

        return countDependenciesResolved
    }

    // Handle classes annotated with InjectRegisterShared
    // DeepLinksHandlerUtil
    internal var deepLinksHandlerUtil: DeepLinksHandlerUtil {
        return getOverriddenInstance() ??
            self.newDeepLinksHandlerUtil
    }
    private var newDeepLinksHandlerUtil: DeepLinksHandlerUtil {
        return AppDeepLinksHandlerUtil()
    }
    // NotificationUtil
    internal var notificationUtil: NotificationUtil {
        return getOverriddenInstance() ??
            self.newNotificationUtil
    }
    private var newNotificationUtil: NotificationUtil {
        return NotificationUtil()
    }
    // SettingsService
    internal var settingsService: SettingsService {
        return getOverriddenInstance() ??
            self.newSettingsService
    }
    private var newSettingsService: SettingsService {
        return SettingsService(storage: self.storage)
    }
    // Storage
    internal var storage: Storage {
        return getOverriddenInstance() ??
            self.newStorage
    }
    private var newStorage: Storage {
        return Storage(userDefaults: self.userDefaults)
    }
    // UserDefaults (custom. property getter provided via extension)
    internal var userDefaults: UserDefaults {
        return getOverriddenInstance() ??
            self.customUserDefaults
    }
}

// swiftlint:enable all
