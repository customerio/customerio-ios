[s-tracking]: https://github.com/customerio/customerio-ios/blob/1.0.0-alpha.5/Sources/Tracking/Tracking.swift
[s-cioerror]: https://github.com/customerio/customerio-ios/blob/1.0.0-alpha.5/Sources/Tracking/CustomerIOError.swift
[s-ciomock]: https://github.com/customerio/customerio-ios/blob/1.0.0-alpha.5/Sources/Tracking/autogenerated/AutoMockable.generated.swift#L101-L152
[s-trackingmock]: https://github.com/customerio/customerio-ios/blob/1.0.0-alpha.5/Sources/Tracking/autogenerated/AutoMockable.generated.swift#L687-L692
[s-cioerrorparse]: https://github.com/customerio/RemoteHabits-iOS/blob/1.0.0/Remote%20Habits/Util/CustomerIOErrorUtil.swift

![min swift version is 5.3](https://img.shields.io/badge/min%20Swift%20version-5.3-orange)
![min ios version is 13](https://img.shields.io/badge/min%20iOS%20version-13-blue)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](code_of_conduct.md) 

# Summary

This is the official Customer.io SDK for iOS.

You'll find our [complete SDK documentation at https://customer.io/docs/sdk/ios](https://customer.io/docs/sdk/ios/). This readme only contains basic information to help you install and initialize the SDK.

Before you get started, keep in mind:
1. **The SDK has been tested on iOS devices**. It might work on other Apple devices—macOS, tvOS, and watchOS—but we have not officially tested, nor do we officially support, non-iOS devices.
2. **Our SDK is a work in progress!** While we're *very* excited about it, it's still in its **`alpha`** phase; it is not ready for general availability. If you want to try it out, contact [product@customer.io](mailto:product@customer.io) and we'll help set you up!

# Get started

To get started, you need to install and initialize the relevant SDK packages in your project. 

To minimize our SDK's impact on your app's size, we offer multiple, separate SDKs. You should only install the packages that you need for your project. 

> Tip: Check out our [sample iOS app, Remote Habits](https://github.com/customerio/RemoteHabits-iOS), for a real-world example of how to use our SDK. 

## Install the SDK

Use the Swift Package Manger to install our SDKs into your project.

1. In Xcode, go to **File** > **Swift Packages** > **Add Package Dependency**

2. In the window that appears, enter the iOS SDK's GitHub repository: 

```
https://github.com/customerio/customerio-ios.git
```

3. Select the version that you want to install. While the SDK is its alpha stage, we recommend that you install *an exact* version of the SDK instead of indicating a range. This prevents you from automatically upgrading to a newer alpha version and possibly installing breaking changes on your code base. 

![in xcode select Exact from dropdown when selecting the version of the SDK to install](docs/img/xcode_spm_install_version.jpg)

4. Lastly, choose the SDK products that you want to install. You can start by selecting `Tracking` for now and adding others later if you need them. 

![](docs/img/xcode_spm_select_sdks.jpeg)

### Available SDK packages

Here are the list of the SDKs that you can install. You can find more details on both in [our SDK documentation](/docs/sdk/ios/).

| Package | Required? | Description |
| :-- | :---: | :--- |
| Tracking | Yes | `identify` people in Customer.io |
| MessagingPushAPN | No | Receive push notifications over Apple's Push Notification service (APNs) |
| MessagingPushFCM | No | Receive push notifications over Firebase Cloud Messaging (FCM) |


## Initialize the SDK

Before you can use the Customer.io SDK, you need to initialize it. Any calls that you make to the SDK before you initialize it are ignored. 

There are two ways to initialize the SDK. The method you use depends on how you want to use the SDK:

1. Singleton, shared instance (the quick and easy way):

When you use the shared instance, you don't need to manage your own instances of Customer.io SDK classes. To get started, initialize the SDK in the `AppDelegate` `application(_ application: didFinishLaunchingWithOptions)` function: 

```swift
import CioTracking

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CustomerIO.initialize(siteId: "YOUR SITE ID", apiKey: "YOUR API KEY")

        // You can optionally provide a Region to set the Region for your Workspace:
        CustomerIO.initialize(siteId: "YOUR SITE ID", apiKey: "YOUR API KEY", region: Region.EU)

        return true
    }
}
```

Then, when you want to use any of the SDK features, you use the shared instance of the class:

```swift
MessagingPush.shared.application(...)
```

2. Create your own instances (better for projects using automated tests):

We recommend that you create your own instances of SDK classes if your project has automated tests. We designed our SDK with first-class support for dependency injection and mocking, which makes it easier to write automated tests. See [testing](#Testing) for more information.

> **Note**: Code samples in this readme use the singleton, shared instance method to call the SDK. However, all samples will also work with your own instances of SDK classes.

```swift
import CioTracking

let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY")

// You can optionally provide a Region to set the Region for your Workspace:
let customerIO = CustomerIO(siteId: "XXX", apiKey: "YYY", region: Region.EU)
```

Then, when you want to use any of the SDK features, you use the shared instance of the class:

```swift
let messagingPush = MessagingPush(customerIO: customerIO)

messagingPush.application(...)
```

# More information

See our complete SDK documentation at [https://customer.io/docs/sdk/ios/](https://customer.io/docs/sdk/ios/)

# Contributing

Thanks for taking an interest in our project! We welcome your contributions. Check out [our development instructions](docs/dev-notes/DEVELOPMENT.md) to get your environment set up and start contributing.

> **Note**: We value an open, welcoming, diverse, inclusive, and healthy community for this project. We expect all  contributors to follow our [code of conduct](CODE_OF_CONDUCT.md). 

# License

[MIT](LICENSE)

