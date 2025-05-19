<p align=center>
  <a href="https://customer.io">
    <img src="https://avatars.githubusercontent.com/u/1152079?s=200&v=4" height="60">
  </a>
</p>

![min swift version is 5.3](https://img.shields.io/badge/min%20Swift%20version-5.3-orange)
![min ios version is 13](https://img.shields.io/badge/min%20iOS%20version-13-blue)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](code_of_conduct.md) 
[![codecov](https://codecov.io/gh/customerio/customerio-ios/branch/develop/graph/badge.svg?token=IZ9RP9XD1O)](https://codecov.io/gh/customerio/customerio-ios)

# Customer.io iOS SDK

This is the official Customer.io SDK for iOS.

**The SDK has been tested on iOS devices**. It might work on other Apple devices—tvOS, and watchOS—but we have not officially tested, nor do we officially support, non-iOS devices.


# Getting started 

You'll find our [complete SDK documentation at https://docs.customer.io/integrations/sdk/ios](https://docs.customer.io/integrations/sdk/ios), but here's a quick start guide to get you up and running.
For complete implementation examples, check out our sample apps in the repository:
- [APN UIKit Sample](/Apps/APN-UIKit)
- [FCM CocoaPods Sample](/Apps/CocoaPods-FCM)

Below, you'll find the necessary steps to set up the SDK.

 ## Quick Reference

  | Section | Description |
  |---------|-------------|
  | [Installation](#1-install-sdk) | Install SDK via SPM or CocoaPods |
  | [Initialization](#2-initialize-sdk) | Configure and initialize the SDK |
  | [User Identification](#3-identify-user-and-track-events) | Identify users and their attributes |
  | [Event and Screen Tracking](#track-events) | Track custom events and screen views |
  | [Push Notifications](#4-initialize-push-notifications) | Set up APNs and FCM push notifications |
  | [In-App Messaging](#5-initialize-in-app-messaging) | Configure in-app messaging |
  | [Testing and Troubleshooting](#testing-push-notifications) | Common issues and solutions |
  | [Sample Apps](#sample-apps) | Example implementations |
  | [Migration Guide](#migrating-from-an-older-sdk-version) | Upgrade from previous versions |
  | [visionOS Support](#visionos-support) | Using SDK with visionOS |


## 1. Install SDK

### Swift Package Manager (SPM) - Recommended
1. In Xcode, select `File > Add Package Dependencies`
2. Enter the package URL: `https://github.com/customerio/customerio-ios.git`

### CocoaPods
Add the pods to your Podfile:
```pod
pod 'CustomerIO/DataPipelines'  # Required
pod 'CustomerIO/MessagingPushAPN'  # Optional, for APNS
pod 'CustomerIO/MessagingPushFCM'  # Optional, for FCM
pod 'CustomerIO/MessagingInApp'  # Optional, for in-app messaging
```

Then run:
```bash
pod install
```

## 2. Initialize SDK

1. First, import the necessary packages in your AppDelegate.swift file:
```swift
import CioDataPipelines
import CioMessagingInApp  // If using in-app messaging
import CioMessagingPushAPN  // If using Apple Push Notifications
// import CioMessagingPushFCM  // If using Firebase Cloud Messaging
```

2. The simplest way to integrate is by using our App Delegate Wrapper
To find the site ID and API Key:
  - open `https://fly.customer.io` in your browser
  - go to your Workspace Settings, then under the `Advanced` section, open `API and webhook credentials`


### UIKit integration
Extend your `AppDelegate` with CustomerIO initialization and add `CioAppDelegateWrapper`:

```swift
@main
class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure and initialize the Customer.io SDK
        let cdpApiKey = "YOUR_CDP_API_KEY"
        let siteId = "YOUR_SITE_ID" // For migration and in-app messaging
        
        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
            .migrationSiteId(siteId) // only required for migration
            .autoTrackUIKitScreenViews() // automatically track UIKit screen views
            .logLevel(CioLogLevel.debug) // add this to troubleshoot the issues - disable `debug` in production
            .build()
        
        CustomerIO.initialize(withConfig: config)
        
        // Initialize push and in-app modules (more details in sections below)
        
        return true
    }
}

```

### SwiftUI integration
Use `CioAppDelegateWrapper` for App's AppDelegate.

```swift
@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(CioAppDelegateWrapper<AppDelegate>.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
        }
    }

}
```

Extend your `AppDelegate` with CustomerIO initialization:

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure and initialize the Customer.io SDK
        let cdpApiKey = "YOUR_CDP_API_KEY"
        let siteId = "YOUR_SITE_ID" // For migration and in-app messaging
        
        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
            .migrationSiteId(siteId) // only required for migration
            .autoTrackUIKitScreenViews() // automatically track UIKit screen views
            .logLevel(CioLogLevel.debug) // add this to troubleshoot the issues - disable `debug` in production
            .build()
        
        CustomerIO.initialize(withConfig: config)
        
        // Initialize push and in-app modules (more details in sections below)
        
        return true
    }
}
```


## 3. Identify User and Track Events

### Identify a User

When a user logs in, identify them with the Customer.io SDK:
```swift
// In your login screen or authentication flow
func onUserLoggedIn(userId: String, userAttributes: [String: Any]) {
    // Identify the user to Customer.io
    CustomerIO.shared.identify(
        userId: userId, 
        traits: userAttributes // Optional user attributes
    )
}
```

### Track Events

Track custom events to trigger campaigns or record user activity:
```swift
// Track events with optional properties
CustomerIO.shared.track(
    name: "product_viewed",
    properties: [
        "product_id": "SKU-123",
        "product_name": "Premium Widget",
        "price": 99.99
    ]
)

// Simple event without properties
CustomerIO.shared.track(name: "checkout_started")
```

### Screen Tracking

If you've enabled automatic screen tracking with `.autoTrackUIKitScreenViews()`, the SDK will automatically track UIKit screen views. 

For manual screen tracking:
```swift
CustomerIO.shared.screen(name: "Product Details", properties: ["product_id": "SKU-123"])
```

## 4. Initialize Push Notifications

### Apple Push Notification Service (APNs)
1. Follow Apple's instructions to enable push notification capabilities in your app
2. Initialize the Push module after initializing the main SDK:
```swift
// In your AppDelegate's didFinishLaunchingWithOptions
MessagingPushAPN.initialize(withConfig: MessagingPushConfigBuilder().build())
```
3. Request permission for push notifications:
```swift
// Request user permission for push notifications
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
    // You can process user response here
}
```

Note: The SDK will automatically register the device token with Customer.io.

### Firebase Cloud Messaging (FCM)

1. Follow Firebase's instructions to set up FCM in your app.
2. Initialize the FCM Push module after initializing the main SDK:
```swift
// Import FirebaseCore and FirebaseMessaging
import FirebaseCore
import FirebaseMessaging
import CioMessagingPushFCM

// In your AppDelegate's didFinishLaunchingWithOptions
FirebaseApp.configure()

MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder().build())
```

Note: The SDK will automatically register FCM tokens with Customer.io.

## 5. Initialize In-App Messaging
To find the site ID:
  - open `https://fly.customer.io` in your browser
  - go to your Workspace Settings, then under the `Advanced` section, open `API and webhook credentials`

1. Initialize the In-App Messaging module after initializing the main SDK:
```swift
// In your AppDelegate's didFinishLaunchingWithOptions
MessagingInApp.initialize(
    withConfig: MessagingInAppConfigBuilder(
        siteId: "YOUR_SITE_ID"
    )
)
```

2. Set up an event listener to respond to in-app message events (optional):
```swift
// In your AppDelegate, first set the event listener
MessagingInApp.shared.setEventListener(self)

// Then implement the event listener protocol
extension AppDelegate: InAppEventListener {
    func messageShown(message: InAppMessage) {
        print("Message shown: \(message.messageId)")
    }
    
    func messageDismissed(message: InAppMessage) {
        print("Message dismissed: \(message.messageId)")
    }
    
    func errorWithMessage(message: InAppMessage) {
        print("Error with message: \(message.messageId)")
    }
    
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        print("Action taken on message: \(message.messageId)")
        
        // Optional: Dismiss the message programmatically
        if actionName == "close" {
            MessagingInApp.shared.dismissMessage()
        }
    }
}
```

3. To create an in-app view and design a message, follow these instructions: https://docs.customer.io/integrations/sdk/ios/in-app/inline-in-app/

## Common Use Cases and Tips

### Testing Push Notifications
- To send a test push notification to your device:
  - open `https://fly.customer.io` in your browser
  - go to your Workspace Settings, then under the `Messaging` section, open `Push`
- Ensure your device token is registered by checking in the Customer.io workspace under the user's profile

### Troubleshooting
- If no events are appearing in Customer.io, check that your site ID and API Key are correct
- Verify that your device has an internet connection
- Remember that the SDK queues requests and will send them when:
  - There are 20+ items in the queue
  - 30 seconds have passed since the last API call
  - The app is reopened
- Enable DEBUG logs with `.logLevel(CioLogLevel.debug)` (more details in section `Initialize SDK` above)
- For more details about troubleshooting check full documentation at https://docs.customer.io/integrations/sdk/ios


## Sample apps
For complete implementation examples, check out our sample apps in the repository:
- [APN UIKit Sample](/Apps/APN-UIKit)
- [FCM CocoaPods Sample](/Apps/CocoaPods-FCM)


## Migrating from an older SDK version? 

Please follow the relevant migration guide for your current SDK version in our [migration docs](https://docs.customer.io/integrations/sdk/ios/migrate-upgrade/).


## visionOS Support

This SDK supports visionOS. We have a handy [sample app](Apps/VisionOS/README.md) that demonstrates how to use the Customer.io iOS/Swift SDK. You can find the sample app in the `Apps/VisionOS` directory.

We've only tested our SDK with visionOS using Swift Package Manager. If you use CocoaPods, everything might work, but we can't guarantee it. 

### visionOS Limitations

While our SDK supports visionOS, there are some limitations:
* We don't support the `MessagingPushFCM` package for visionOS. You must send push notifications over APNS.
* We don't support in-app messaging (the `MessagingInApp` package) for visionOS.


# Contributing

Thanks for taking an interest in our project! We welcome your contributions. Check out [our development instructions](docs/dev-notes/DEVELOPMENT.md) to get your environment set up and start contributing.

> **Note**: We value an open, welcoming, diverse, inclusive, and healthy community for this project. We expect all  contributors to follow our [code of conduct](CODE_OF_CONDUCT.md). 

# License

[MIT](LICENSE)
