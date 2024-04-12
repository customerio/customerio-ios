# VisionOS Sample App

The VisionOS Sample App is a practical demonstration to help you integrate and use the Customer.io iOS/Swift SDK.

## Who Is This App For?

This sample app is designed for VisionOS and iOS developers who want to get hands-on experience with Customer.io's code samples. It's a tool to help you validate, debug, or enhance your understanding of Customer.io's APIs.

## Run the App

Before running the app, you must have one of the following:
* The Apple Vision Pro simulator, which you can download from Xcode.
* An Apple Vision Pro device with developer mode enabled.

To run the app:

1. Clone the [customerio-ios](https://github.com/customerio/customerio-ios) repository:
   ```
   git clone https://github.com/customerio/customerio-ios
   ```
2. Go to `<REPO_ROOT_DIR>/Apps/VisionOS` and open `VisionOS.xcodeproj` with Xcode.
3. Ensure that the `VisionOS` scheme is selected and set to run on the simulator or your device.
4. Click **Run** in Xcode or press `CMD+R`.

## How to Use the App

### Prerequisites
1. You must have a Customer.io account. [Sign up for a free trial](https://fly.customer.io/signup) if you haven't already.
2. While you don't need to go through a complete workspace setup to use the sample app, you do need to set up an iOS source in Data Pipelines. As a part of this setup, you'll get the CDP API key that you'll use to initialize the SDK. [Learn more](https://customer.io/docs/sdk/ios/getting-started/auth/#set-up-a-new-source).

### MainScreen.swift
`MainScreen.swift` contains the executable code samples that the app's UI uses during interactions. Place breakpoints in this file's `switch` case to inspect actions performed by the app.

### AppDelegate.swift
The SDK is initialized when you enter the `CDP API key` and tap `Initialize` on the **Initialize** screen. In a production app, you would typically initialize the SDK in your `AppDelegate`. Therefore, you will find SDK initialization code in both `MainScreen.swift` and `AppDelegate.swift`. If you don't want to set the CDP API Key in the UI, you can hardcode it in the app delegate while you explore other APIs in the app.

### The UI
The app features a navigation menu to help you move between examples:

* At first, only the **Initialize** example is active. You must initialize the SDK before you can do anything else.
* After setting the CDP API key and initializing, other examples become available for you to explore.

### Debug Mode Configurations
The app's code is tailored for debug mode, with `logLevel` set to `debug`. After most `CustomerIO.shared.*` calls, you will notice a `CustomerIO.shared.flush()` call. These configurations are beneficial during debugging as they provide:

- Detailed logs offering immediate feedback during development and debugging. For example, try using the initialize functionality again after the first setup to observe the corresponding log message.
- The `CustomerIO.shared.flush()` call circumvents network queue optimizations, so you'll see your data immediately in Customer.io Data Pipelines.

### End-to-End Examples
To fully grasp the integration, observe how data sent from the SDK appears in the data pipelines:

1. Visit your [dashboard](https://fly.customer.io/workspaces/sources).
2. Select 'Sources' from the left menu and choose the iOS source representing the CDP API key you used to initialize the app.
3. Click the `Data In` tab.

As you interact with different SDK APIs, you should see the corresponding data in this tab.

**Bonus:**
Try connecting your source to a destination and observe how the data is mapped from the Vision Pro source to the destination platform where you'll use that data.

## Support and limitations

We've only tested our SDK with visionOS using Swift Package Manager. If you use CocoaPods, everything might work but we can't guarantee it. 

visionOS support has some known limitations:
* We don't support the `MessagingPushFCM` package for visionOS. You must send push notifications over APNS.
* We don't support in-app messaging (the `MessagingInApp` package) for visionOS.