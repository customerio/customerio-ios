# Linux 

Swift packages have the ability to easily be installed on iOS, mac, other Apple technologies but also Linux. This document discusses the SDK's support for Linux - not how to develop the code base with Linux or any other Linux related question. 

# Linux support

The Customer.io iOS SDK at this time does not provide official support for Linux. This means that we do not recommend you use our SDK in production on Linux but in our development, we are currently trying our best to support Linux. 

Why does the project not provide official support but we still write code to support Linux? 
* *Following the Swift trend* - The Swift project + community are continuously trying to support Linux in projects. If and when Linux support with Swift is more stable, we may decide to officially support Linux. By writing code today to support Linux, we are showing our efforts to support Linux. 
* *Get Linux support for free!* - When the [Foundation framework](https://github.com/apple/swift-corelibs-foundation) is fully compatible and stable with Linux, our SDK should *just work* on Linux. When trying to make a decision on how to implement a feature in the SDK, try to use a solution that is compatible with Linux. 
* *Write code that can support more OSes in the future, easily* - This SDK project aims to support multiple OSes that Swift supports (iOS, macOS, watchOS, etc). If you were to ignore Linux entirely and write code just for iOS let's say, you are creating more technical debt on yourself to support other OSes. By trying to support Linux, our code base has some design decisions made to be ready to support more OSes in the future. 

# Notes about Linux support in this project

### Disabled integration tests for using FileManager 

Some tests have been disabled for Linux in the project. These tests are specifically integration tests using `FileManager` that work with a real file system. These tests have been disabled because at the time of this writing, tests have executed flaky on Linux. 

We are expecting that once [FileManager has a more stable status](https://github.com/apple/swift-corelibs-foundation/blob/main/Docs/Status.md) on Linux, we should be able to enable these tests and they should work as expected. All tests run and pass on iOS so therefore, we expect them to pass as expected on Linux, too. 

You can find these tests in the code base by searching for the comment `LINUX_DISABLE_FILEMANAGER`. 