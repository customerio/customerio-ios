<p align="center">
  <a href="https://customer.io">
    <img src="https://user-images.githubusercontent.com/6409227/144680509-907ee093-d7ad-4a9c-b0a5-f640eeb060cd.png" height="60">
  </a>
  <p align="center">Power automated communication that people like to receive.</p>
</p>

![min swift version is 5.3](https://img.shields.io/badge/min%20Swift%20version-5.3-orange)
![min ios version is 13](https://img.shields.io/badge/min%20iOS%20version-13-blue)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](code_of_conduct.md) 
[![codecov](https://codecov.io/gh/customerio/customerio-ios/branch/develop/graph/badge.svg?token=IZ9RP9XD1O)](https://codecov.io/gh/customerio/customerio-ios)

# Customer.io iOS SDK

This is the official Customer.io SDK for iOS.

You'll find our [complete SDK documentation at https://customer.io/docs/sdk/ios](https://customer.io/docs/sdk/ios/). 

**The SDK has been tested on iOS devices**. It might work on other Apple devices—macOS, tvOS, and watchOS—but we have not officially tested, nor do we officially support, non-iOS devices.

### Migrating from an older SDK version? 

Please follow the relevant migration guide for your current SDK version in our [migration docs](https://customer.io/docs/sdk/ios/migrate-upgrade/).

## Summary

To get started, you need to install and initialize the relevant SDK packages in your project. 

We've separated our SDK into packages to minimize our impact on your app's size. You should only install the packages that you need for your project. 

| Package | Required? | Description |
| :-- | :---: | :--- |
| Tracking | Yes | [`identify`](https://customer.io/docs/sdk/ios/identify/) people/devices and [send events](https://customer.io/docs/sdk/ios/track-events/) (to trigger campaigns, track metrics, etc). |
| MessagingPushAPN | No | [Push](https://customer.io/docs/sdk/ios/push/) and [rich push](https://customer.io/docs/sdk/ios/rich-push/) notifications using Apple's Push Notification service (APNs). |
| MessagingPushFCM | No | [Push](https://customer.io/docs/sdk/ios/push/) and [rich push](https://customer.io/docs/sdk/ios/rich-push/) notifications using Firebase Cloud Messaging (FCM). |

## visionOS Support

This SDK supports visionOS. We have a handy [sample app](Apps/VisionOS/README.md) that demonstrates how to use the Customer.io iOS/Swift SDK. You can find the sample app in the `Apps/VisionOS` directory.

We've only tested our SDK with visionOS using Swift Package Manager. If you use CocoaPods, everything might work, but we can't guarantee it. 

Also, for now, we *only* support Apple's Push Notification Service (APNS) for visionOS. You won't be able to send push notifications to Vision Pro devices using Firebase Cloud Messaging (FCM).

# Getting started 

See our complete SDK documentation at [https://customer.io/docs/sdk/ios/](https://customer.io/docs/sdk/ios/)

# Contributing

Thanks for taking an interest in our project! We welcome your contributions. Check out [our development instructions](docs/dev-notes/DEVELOPMENT.md) to get your environment set up and start contributing.

> **Note**: We value an open, welcoming, diverse, inclusive, and healthy community for this project. We expect all  contributors to follow our [code of conduct](CODE_OF_CONDUCT.md). 

# License

[MIT](LICENSE)
