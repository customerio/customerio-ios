# Linux 

Swift packages have the ability to easily be installed on iOS, macOS, other Apple technologies, and also Linux. This document discusses the SDK's support for Linux - not how to develop the code base with Linux or any other Linux related question. 

# Linux support

The Customer.io iOS SDK at this time does not provide official support for Linux. If you are looking to use this SDK in a linux project, please let us know at `win@customer.io`. 

# Notes about Linux support in this project

### Disabled integration tests for using FileManager 

Some tests have been disabled for Linux in the project. These tests are specifically integration tests using `FileManager` that work with a real file system. These tests have been disabled because at the time of this writing, tests have executed flaky on Linux. 

We are expecting that once [FileManager has a more stable status](https://github.com/apple/swift-corelibs-foundation/blob/main/Docs/Status.md) on Linux, we should be able to enable these tests and they should work as expected. All tests run and pass on iOS so therefore, we expect them to pass as expected on Linux, too. 

You can find these tests in the code base by searching for the comment `LINUX_DISABLE_FILEMANAGER`. 

### Disabled swift testing on Linux on CI server

When the in-app SDK was added to the project, we had to disable running test with `swift` (compared to running with xcode). This was because we added a dependency (Gist) into the SDK project that requires being compiled with iOS as a target. 