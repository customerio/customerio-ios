# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Customer.io iOS SDK - Developer Guide

After completing planned changes to the code, ALWAYS build the code to make sure it's working, before continuing to the next step.
After making changes to Unit Tests, ALWAYS test changed test classes. Avoid testing the whole module or the whole SDK, unless absolutely necessary.

## Commands
- Build the single module: `xcodebuild -scheme MODULE_NAME -configuration Debug -workspace ~/Development/customerio-ios/.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -allowProvisioningUpdates build`
  - More details in section `Building` below
- Test single file (with xcodebuild): `xcodebuild test-without-building -workspace ./.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -scheme Customer.io-Package -only-testing:TestSuiteName/TestClassName`
  - More details in section `Testing` below
- Format: `make format` (run before lint)
- Lint: `make lint`
- Generate code and mocks: `make generate`
  - After `make generate`, always run first `make format` and then `make lint`

## Code Style
- Swift 5.3+ with protocol-oriented design
- Naming: CamelCase for types, camelCase for properties/methods
- Descriptive method names (e.g., `identify`, `registerDeviceToken`)
- Always use constructor-based dependency injection pattern, and use `DIGraphShared` only for top level module initialization
- Modular architecture (Common, DataPipeline, MessagingPush, etc.)
- Document public APIs with doc comments
- Always add doc comments to Protocol, no mether are those public or internal. When component implements protocol, do not repeat the same docs.
- Error handling: prefer `throws`/`do-try-catch`, but use Result types when existing code is using it
- Avoid force unwrapping (!) except in tests
- Keep methods small and focused

## Project Structure
- `Sources/` - Main SDK code organized by modules:
  - `Common/` - Shared core functionality
  - `DataPipeline/` - Customer identification and event tracking
  - `MessagingPush/` - Base push notification functionality
  - `MessagingPushAPN/` - Apple Push Notification implementation
  - `MessagingPushFCM/` - Firebase Cloud Messaging implementation
  - `MessagingInApp/` - In-app messaging functionality
  - `Migration/` - Migration tools for version upgrades
  - `Templates/` - Sourcery templates for code generation
- `Tests/` - Test files organized by module
- `Apps/` - Sample applications demonstrating SDK usage

## Architecture

### Module Architecture
- Each module exposes a public-facing facade extending `ModuleTopLevelObject`
- Implementation classes are hidden from SDK users
- Public protocols define the interface contracts
- Builder pattern for configuration options

### Initialization Pattern
```swift
// Configure module with builder pattern
let config = DataPipelineConfigBuilder()
    .siteId("your-site-id")
    .apiKey("your-api-key")
    .build()

// Initialize the module
DataPipeline.initialize(moduleConfig: config)

// Use the shared instance
DataPipeline.shared.identify(userId: "customer-id")
```

### Dependency Injection
- Always use constructor based dependency injection pattern
- `DIGraphShared` serves as the central dependency registry, which should be used only for top level module initialization
- Modules obtain dependencies through constructor injection
- Avoid Singleton pattern when ever you can
- Thread-safe access via `Swift Structured Concurrency` and `@Atomic` property wrapper
- Testing uses override mechanism to substitute components

### Inter-Module Communication
- Event-based architecture using `EventBus`
- Type-safe event publishing and subscription
- Modules can react to events without direct dependencies
- Key events include profile identification, device token registration, etc.

## Building

After completing planned changes to the code, ALWAYS compile to make sure it's working, before continuing to the next step.

#### Detect available Simulators
Before building the code, ALWAYS use following command to detect available Simulators:
```bash
xcrun simctl list devices available
```
Prefer to use already Booted Simulators.

### Building single module
Example:
```bash
xcodebuild -scheme MessagingPushAPN -configuration Debug -workspace ~/Development/customerio-ios/.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -allowProvisioningUpdates build
```

### Building the whole SDK
Example:
```bash
xcodebuild -scheme Customer.io-Package -configuration Debug -workspace ~/Development/customerio-ios/.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -allowProvisioningUpdates build
```

## Testing

### Test Structure

- **Base Test Classes**: 
  - `UnitTestBase<Component>`: Generic base class for all tests, supporting different module interfaces
  - `UnitTest`: Convenience subclass of `UnitTestBase<CustomerIO>` for SDK-wide tests
  - Module-specific test bases (e.g., `DataPipeline/UnitTest`) extend the shared base class

### Test Types

- **Unit Tests**: Test individual components in isolation
  - Focus on specific functions and classes
  - Heavy use of mocks and stubs
  - Run synchronously for predictability

- **Integration Tests**: Test interactions between components
  - Less mocking, closer to real behavior
  - Test module initialization and communication
  - Extend unit test classes with additional setup for more realistic environments

### Mocking Strategy

- **Auto-Generated Mocks**: 
  - Created via Sourcery using protocols marked with `AutoMockable`
  - Generated into module's `autogenerated` directory
  - Track invocation counts, arguments, and return values
  - Managed by central `Mocks.shared` registry for automatic cleanup

- **Manual Stubs**: 
  - Implement specific behaviors needed for tests
  - Used for system interfaces (DeviceInfo, DateUtil, etc.)
  - Stored in `Tests/Shared/Stub` directory

### Testing Utilities

- **DIGraph Overrides**: Dependency injection enables replacing components for testing
  - `diGraphShared.override(value:forType:)` for swapping implementations
  - Reset between tests to maintain isolation

- **Test Environment Management**:
  - `setUp()`: Configures test environment and dependencies
  - `cleanupTestEnvironment()`: Removes test artifacts
  - `deleteAllPersistentData()`: Ensures test isolation

- **Async Testing Helpers**:
  - `waitForAsyncOperation`: Simplifies testing async code
  - `runOnBackground`: Executes code in background 
  - Thread util stubbing to make async code run synchronously

- **Verification Utilities**:
  - Custom matchers for deeply comparing objects
  - Sample data files for consistent test data
  - OutputReaderPlugin for validating event tracking behavior

### Testing Patterns

- Extensive use of XCTest assertions
- Test doubles follow AAA pattern (Arrange, Act, Assert)
- Always use clear named test functions following `testMethodName_whenCondition_thenResult` format
- Tests check both state and behavior
- Emphasis on test isolation through proper setup/teardown

### Running Tests

#### Detect available Simulators
Before building or tests, ALWAYS use following command to detect available Simulators:
```bash
xcrun simctl list devices available
```
Prefer to use already Booted Simulators.

#### Build the code before testing
If you running the test for the first time in the session, or changes have been made, rebuild the code for testing.
Example:
```bash
xcodebuild build-for-testing -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -allowProvisioningUpdates -scheme Customer.io-Package -workspace ~/Development/customerio-ios/.swiftpm/xcode/package.xcworkspace
```

#### Command Line with xcodebuild
To run tests from the command line with xcodebuild:

```bash
xcodebuild test-without-building -workspace /path/to/package.xcworkspace -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -scheme Customer.io-Package -only-testing:TestSuiteName/TestClassName
```

Example:
```bash
xcodebuild test-without-building -workspace ./.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=A7D4BD50-572C-491A-9713-4A3B9DB04B44' -scheme Customer.io-Package -only-testing:MessagingPushTests/CioProviderAgnosticAppDelegateTests
```

To run all tests in a suite:
```bash
xcodebuild test-without-building -workspace ./.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=A7D4BD50-572C-491A-9713-4A3B9DB04B44' -scheme Customer.io-Package -only-testing:MessagingPushTests
```
