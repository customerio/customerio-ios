# VisionOS Sample App

The VisionOS Sample App is a practical demonstration of how to integrate and utilize the Customer.io Data Pipelines iOS/Swift SDK.

## Who Is This App For?

This sample app is designed for VisionOS and iOS developers who are looking to get hands-on experience with Customer.io's code samples. It serves as a tool to validate, debug, or enhance their understanding of the different Customer.io APIs.

## Run the App

Before running the app, ensure you have one of the following prerequisites:
* Apple Vision Pro simulator, which can be downloaded from Xcode.
* An Apple Vision Pro device with developer mode enabled.

To run the app, follow these steps:

1. Clone the [customerio-ios](https://github.com/customerio/customerio-ios) repository by executing:
   ```
   git clone https://github.com/customerio/customerio-ios
   ```
2. Navigate to `<REPO_ROOT_DIR>/Apps/VisionOS` and open the `VisionOS.xcodeproj` file with Xcode.
3. Ensure the `VisionOS` scheme is selected and set to run on either the simulator or your device.
4. Click the run button in Xcode or press `CMD+R`.

## How to Use the App

### Prerequisites
1. You must have a Customer.io account. Sign up for a free one if you haven't already.
2. While a full workspace setup is not required for this sample app, you do need to set up an iOS Data Pipeline source and use its CDP API key to initialize the SDK. [Learn more](https://customer.io/docs/sdk/ios/getting-started/auth/#set-up-a-new-source).

### MainScreen.swift
`MainScreen.swift` contains the executable code samples that the app's UI will use during interaction. Place breakpoints in the `switch` case within this file to inspect any action performed by the app.

### AppDelegate.swift
The SDK is initialized when you enter the `CDP API key` and tap the `Initialize` button on the **Initialize** screen. In a production app, you would typically initialize the SDK in your `AppDelegate`. Therefore, you will find SDK initialization code in both `MainScreen.swift` and `AppDelegate.swift`.

### The UI
The app features a navigation menu that allows you to move between different examples:

* Initially, only the **Initialize** example is active, as the SDK requires initialization to function.
* After setting the CDP API key and initializing, other examples become accessible for exploration.

### Debug Mode Configurations
The app's code is tailored for debug mode, with `logLevel` set to `debug`. After most `CustomerIO.shared.*` calls, you will notice a `CustomerIO.shared.flush()` call. These configurations are beneficial during debugging as they provide:

- Detailed logs offering immediate feedback during development and debugging. For instance, try using the initialize functionality again after the first setup to observe the corresponding log message.
- The `CustomerIO.shared.flush()` call circumvents network queue optimizations, allowing immediate visibility of your data in Customer.io data pipelines.

### End-to-End Examples
To fully grasp the integration, observe how data sent from the SDK appears in the data pipelines:

1. Visit your [data pipeline dashboard](https://fly.customer.io/workspaces/sources).
2. Select 'Sources' from the left menu and choose the source associated with the CDP API key mentioned in the prerequisites.
3. Click on the `Data In` tab.

As you interact with different SDK APIs, you should see the corresponding data in this tab.

**Bonus:**
For those with knowledge of data pipelines or the curious, try linking your source to a destination and observe how the data is distributed to various destinations.