[s-tracking]: https://
[s-cioerror]: https://
[s-ciomock]: https://
[s-trackingmock]: https://

![min swift version is 5.3](https://img.shields.io/badge/min%20Swift%20version-5.3-orange)
![min ios version is 9](https://img.shields.io/badge/min%20iOS%20version-9-blue)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](code_of_conduct.md) 

# Customer.io iOS SDK

**This is a work in progress!** While we're *very* excited about it, it's still in its alpha phase; it is not ready for general availability. If you want to try it out, contact [product@customer.io](mailto:product@customer.io) and we'll help set you up!

Before you get started, keep in mind:
1. **The SDK has been tested on iOS devices**. It might work on other Apple devices—macOS, tvOS, and watchOS—but we have not officially tested, nor do we officially support, non-iOS devices.
2. **The SDK is in its `alpha` phase**. Feel free to try it out, but please understand that we might introduce breaking changes to the API and you may experience bugs. 

# Get started

To get started, you need to install and initialize the relevant SDK packages in your project. 

To minimize our SDK's impact on your app's size, we split it into packages. You should only install the packages that you need for your project. Right now, we have one package:

* `Tracking` - Tracking features for customers.

With this package, you can: 
1. [Identify a customer](https://customer.io/docs/identifying-people/) with an ID or email address. 

   * `MessagingPushAPN` - Push notification messaging with Apple Push Notification Service (APN).

1. [Register a device to receive push notifications via APNs](https://customer.io/docs/push-getting-started/). 

> **Note**: We only support APN right now. We plan to support FCM on iOS in a future release.

## Install the SDK

You can get our SDK using the Swift Package Manger. You can install it via your project's `Package.swift` or through XCode (recommended). 

1. In XCode, go to **File** > **Swift Packages** > **Add Package Dependency**. 
2. In the package repository URL field, enter `https://github.com/customerio/customerio-ios`. 

// TODO add screenshots 

3. When asked what version of the SDK to install, select `XXXXXX`

// TODO add screenshot showing what version to select. This can't be done until PR for identify customer merged in. 

## Initialize the SDK

Before you can use the Customer.io SDK, you need to initialize it. Any calls that you make to the SDK before you initialize it are ignored. 

There are two ways to initialize the SDK:

1. Singleton, shared instance (the easy way):

The shared instance of the SDK is easy to set up. When you use the shared instance, you don't need to manage your own instances of Customer.io SDK classes.

```swift
import Cio

CustomerIO.initialize(siteId: "XXX", apiKey: "YYY")

// You can optionally provide a Region to set the Region for your Workspace:
CustomerIO.initialize(siteId: "XXX", apiKey: "YYY", region: Region.EU)
```

Then, when you want to use SDK features, you use the shared instance of the class:

```swift
Tracking.shared.identifyCustomer(...)
```

2. Create your own instances (better for automated tests):

We recommend that you create your own instances of SDK classes if your project has automated tests. We designed our SDK with first-class support for dependency injection and mocking, which makes it easier to write automated tests. See [testing](#Testing) for more information.

> **Note**: Code samples in this readme use the singleton, shared instance method to call the SDK. These samples will also work with your own instances of SDK classes.

```swift
import Cio

let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY")

// You can optionally provide a Region to set the Region for your Workspace:
let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY", region: Region.EU)
```

Then, when you want to use the SDK, you use the singleton instance of the SDK:

```swift
let tracking = Tracking(customerIO: customerIO)

tracking.identifyCustomer(...)
```


<!-- 
### Messaging push

...To be completed after feature complete. 

Instructions will include APN setup instructions as well as code to use the SDK feature. 
-->

# Tracking

## Identify a customer

When you identify a customer, you:
1. Add or update the customer's profile in your workspace.
2. Save the customer's information on the device. Future calls to the SDK represent the last-identified customer. For example, after you identify a person, any events that you track are automatically associated with that person.

You can only identify one customer at a time. The SDK "remembers" the most recently-identified customer.
If you identify customer "A", and then call the identify function for customer "B", the SDK "forgets" customer "A" and assumes that customer "B" is the current app user. 

[Learn more about the `Tracking` class][s-tracking].

```swift
import Tracking

Tracking.shared.identifyCustomer(identifier: "989388339") { result in 
    switch result {
    case .success: 
      // Customer successfully identified in your Workspace!
      break 
    case .failure(let customerIOError):
      // Error occurred. It's recommended you parse `customerIOError` to learn more about the error.
      break 
    }
}

// You can also provide an optional email address to the profile:
Tracking.shared.identifyCustomer(identifier: "989388339", onComplete: { result in 
    // handle `result`
}, email: "great-customer@cool-website.com")
```

## Stop identifying a customer

This class "forgets" the currently identified customer. When you stop identifying someone, calls to the SDK are no longer associated with the previously-identified person. You might want to stop identifying someone when they log out of your app. 

> **Note**: If you simply want to identify a new customer, you don't need to use this call. Simply call `identifyCustomer()` again to identify a new customer and stop identifying the previous one.

```swift
// If no profile has been identified yet, this function will ignore your request.
Tracking.shared.identifyStop()
```

# Error handling 

Whenever there's an error, the SDK returns a `CustomerIOError`. The `Error` subclass helps you understand and handle the error. [Learn more about the `CustomerIOError` class][s-cioerror].

```swift
let error: CustomerIOError = ...

switch error {
case .httpError(let httpError):
    // An error happened while performing a HTTP request. 
    // `httpError` is an instance of `HttpRequestError` and can also be parsed:
    switch httpError {        
    ...
    }
    break
case .underlyingError(let error):
    // A miscellaneous error happened. Parse `error` as you would any other `Swift.Error`. 
    break 
}
```

# Testing 

We designed the SDK with first-class support for automated testing, making it easy to inject dependencies and perform mocking in your code.

## Dependency injection

Every SDK class has an inherited protocol. Inherited protocols use a consistent naming convention: `NameOfClassInstance`. For example, the tracking class inherits the `TrackingInstance` protocol. 

If you want to inject a class in your project, it could look something like this:

```swift
class ProfileRepository {
    
    private let cioTracking: TrackingInstance

    init(cioTracking: TrackingInstance) {
        self.cioTracking = cioTracking
    }

    // Now, you can call call any of the `Tracking` class functions with `self.cioTracking`!
    func loginUser(email: String, password: String, onComplete: @escaping (Result<Success, Error>) -> Void) {
        // login the user to your system. If successful, 
        self.cioTracking.identifyCustomer(email) { result in 
            // handle `result` of identifyCustomer() call. 
        }
    }

}

// Provide an instance of the `Tracking` class to your class:
let cioTracking = Tracking(customerIO: customerIOInstance)
let repository = ProfileRepository(cioTracking: cioTracking)
```

## Mocking

Every SDK class has a mock class ready for you to use. That's right, we generated a collection of mocks for you! 

Mock classes follow the naming convention: `NameOfClassMock`. For example, the tracking class's mock class is `TrackingMock`. 

Here's an example test class showing how you would test your `ProfileRepository` class.

```swift
import Foundation
import Tracking
import XCTest

class ProfileRepositoryTest: XCTestCase {
    private var trackingMock: TrackingMock!
    private var repository: ProfileRepository!

    override func setUp() {
        super.setUp()

        trackingMock = TrackingMock() // Create a new instance of the mock in setUp() to reset the mock. 

        repository = ProfileRepository(cioTracking: trackingMock)
    }

    func test_loginUser() {
        // Because the `identifyCustomer()` function returns a result, you must return a result from the mock 
        // using the onComplete callback. 
        trackingMock.identifyCustomerClosure = { identifier, onComplete, email in 
            // You can return a successful result:
            onComplete(Result.success(Void()))
            // Or, return an error. Like here when a request couldn't be made possibly because of a network error. 
            onComplete(Result.failure(CustomerIOError.httpError(.noResponse)))
        }

        // Now, call your function under test:
        repository.loginUser(...)

        // You can access many properties of the mock class to assert the behavior of the mock. 
        XCTAssertTrue(trackingMock.mockCalled)
        XCTAssertEqual(trackingMock.identifyCustomerCallsCount, 1)
        XCTAssertEqual(trackingMock.requestReceivedInvocations[0].identifier, expectedIdentifier)
        // Check out the links below to learn more about the mock classes available to see what they are capable of. 
    }
}
```

Mock classes:
* [`CustomerIOMock`][s-ciomock]
* [`TrackingMock`][s-trackingmock]

# Contributing

Thanks for taking an interest in our project! We welcome your contributions. Check out [our development instructions](docs/dev-notes/DEVELOPMENT.md) to get your environment set up and start contributing.

> **Note**: We value an open, welcoming, diverse, inclusive, and healthy community for this project. We expect all  contributors to follow our [code of conduct](CODE_OF_CONDUCT.md). 

# License

[MIT](LICENSE)
