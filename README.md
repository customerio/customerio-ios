[s-tracking]: https://
[s-cioerror]: https://
[s-ciomock]: https://
[s-trackingmock]: https://

![min swift version is 5.3](https://img.shields.io/badge/min%20Swift%20version-5.3-orange)
![min ios version is 9](https://img.shields.io/badge/min%20iOS%20version-9-blue)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](code_of_conduct.md) 

# Customer.io iOS SDK

Official Customer.io SDK for iOS

**This project is a work in progress and is not yet ready for general availability. If you are interested in being an early user of this SDK for your iOS app, send us a message at `product@customer.io` saying you would like to try out our iOS SDK. We will work with you to get setup!**

Notes:
1. The SDK has been tested on iOS devices. The SDK may work on other Apple devices such as macOS, tvOS, and watchOS but official support and official testing has not been done on these devices. 
2. The SDK is in `alpha` phase at the moment. It is available to use but note that the API will have breaking changes introduced and issues may occur. 

# Getting started

Let's get started using the Customer.io SDK. To do that, we need to install and initialize the SDK into our project. 

### The SDKs

To keep your app size as small as possible, the Customer.io mobile SDK is split into multiple small SDK packages. You should only install what you need for your project. 

Available SDKs to install: 

* `Tracking` - Tracking features for customers.

Features: 
1. [Identify a customer](https://customer.io/docs/identifying-people/) with an ID or email address. 

* `MessagingPushAPN` - Push notification messaging with Apple Push Notification Service (APN). 

Features:
1. [Register a device to receive push notifications via the APN service](https://customer.io/docs/push-getting-started/). 

*Note: APN is only supported at this time. FCM support on iOS is planned for a future release of the SDK.*

### Install SDK

The Customer.io mobile SDK is available to install with the Swift Package Manager. You can install the SDK via your project's `Package.swift` or through XCode (recommended). 

1. In XCode, open `File > Swift Packages > Add Package Dependency`. 
2. When asked to enter package repository URL, copy and paste: `https://github.com/customerio/customerio-ios`. 

// TODO add screenshots 

3. When asked what version of the SDK to install, select `XXXXXX`

// TODO add screenshot showing what version to select. This can't be done until PR for identify customer merged in. 

### Initialize the SDK

In order to use any feature of the Customer.io SDK, you need to initialize the SDK so it knows how to act upon your Workspace. *Note: All calls made sent to the Customer.io SDK will be ignored until you initialize the SDK.*

To initialize the SDK, you have 2 options:

1. Singleton, shared instance:

```swift
import Cio

CustomerIO.initialize(siteId: "XXX", apiKey: "YYY")

// You can optionally provide a Region to set the Region for your Workspace:
CustomerIO.initialize(siteId: "XXX", apiKey: "YYY", region: Region.EU)
```

Now, when you want to use any of the features of the SDK, you use the shared instance of the class:

```swift
Tracking.shared.identifyCustomer(...)
```

Using the shared instance of the SDK is for convenience. It requires little setup and you don't need to worry about managing instances of any Customer.io SDK classes. 

2. Create your own instances:

```swift
import Cio

let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY")

// You can optionally provide a Region to set the Region for your Workspace:
let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY", region: Region.EU)
```

Now, when you want to use any of the features of the SDK, you use the singleton instance of the CustomerIO SDK:

```swift
let tracking = Tracking(customerIO: customerIO)

tracking.identifyCustomer(...)
```

Using your own instances of the SDK classes is recommended for projects with automated tests. The Customer.io SDK has been designed with first-class support for dependency injection and mocking making writing automated tests with Customer.io quick and easy. See the [testing](#Testing) section of these docs to learn more. 

*Note: The code samples in the documentation use the singleton, shared instance method to call the SDK. Know the code samples will also work as expected with your own instance of the SDK classes.*

# Documentation

### Messaging push

...To be completed after feature complete. 

Instructions will include APN setup instructions as well as code to use the SDK feature. 

## Tracking

### Identify a customer

Identifying a customer in the SDK will perform a couple of operations:
1. Add or update a customer profile in your Workspace
2. Save the customer information on the device and use it for all future calls to the SDK. Example: If you track an event, that event will be registered with the identified customer profile automatically for you. 

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

Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
the previously identified profile will be removed. Only the latest identified customer is persisted.

[Learn more about the `Tracking` class][s-tracking]

### Stop identifying a customer

Stop identifying the currently persisted customer. All future calls to the SDK will no longer be associated with the previously identified customer.

```swift
// If no profile has been identified yet, this function will ignore your request.
Tracking.shared.identifyStop()
```

*Note: If you simply want to identify a new customer, this function call is optional. Simply call `identifyCustomer()` again to identify the new customer profile over the existing.*

## Error handling 

All of the features of the Customer.io SDK return a `CustomerIOError` when there is an error returned to you. This `Error` subclass exists as a convenient way for you to find out more about the error and decide how to handle it. 

Here is an example:

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

[Learn more about the `CustomerIOError` class][s-cioerror]

## Testing 

The Customer.io SDK has been designed to provide first-class support for automated testing in your project. This is done by making it quick and easy to perform dependency injection and mocking in your code. 

### Dependency injection

Every class of the SDK has a protocol inherited. The naming is consistent: `NameOfClassInstance`. Example: The tracking class inherits the protocol `TrackingInstance`. 

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

### Mocking

Every class of the SDK has a mock class ready for you to use. That's right, we have generated a collection of mocks for you! 

All mock classes are consistently named: `NameOfClassMock`. Example: The tracking class's mock class is `TrackingMock`. 

Let's see an example test class to see how you would test your `ProfileRepository` class. 

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

Thank you for your interest in wanting to contribute to the project! Let's get your development environment setup so you can get developing.

To contribute to this project, follow the instructions in [our development document](docs/dev-notes/DEVELOPMENT.md) to get your development environment setup. 

> Note: We value an open, welcoming, diverse, inclusive, and healthy community for this project. All contributors are expected to follow the rules set forward in our [code of conduct](CODE_OF_CONDUCT.md). 

# License

[MIT](LICENSE)
