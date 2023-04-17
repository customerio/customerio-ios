// Generated using Sourcery 2.0.2 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CioTracking
import CioMessagingPushAPN

/**
######################################################
Documentation
######################################################

This automatically generated file you are viewing contains mock classes that you can use in your test suite. 

* How do you generate a new mock class? 

1. Mocks are generated from Swift protocols. So, you must make one. 

```
protocol FriendsRepository {
    func acceptFriendRequest(_ onComplete: @escaping () -> Void)
}

class AppFriendsRepository: FriendsRepository {
    ...
}
```

2. Have your new protocol extend `AutoMockable`:

```
protocol FriendsRepository: AutoMockable {
```

3. Run the command `make generate` on your machine. The new mock should be added to this file. 

* How do you use the mocks in your test class? 

```
class ExampleViewModelTest: XCTestCase {
    var viewModel: ExampleViewModel!
    var exampleRepositoryMock: ExampleRepositoryMock!
    override func setUp() {
        exampleRepositoryMock = ExampleRepositoryMock()
        viewModel = AppExampleViewModel(exampleRepository: exampleRepositoryMock)
    }
}
```

Or, you may need to inject the mock in a different way using the DI.shared graph:

```
class ExampleTest: XCTestCase {
    var exampleViewModelMock: ExampleViewModelMock!
    var example: Example!
    override func setUp() {
        exampleViewModelMock = ExampleViewModelMock()
        DI.shared.override(.exampleViewModel, value: exampleViewModelMock, forType: ExampleViewModel.self)
        example = Example()
    }
}

```

*/














