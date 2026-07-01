# Customer.io iOS SDK - Agent and Contributor Guide

Guidance for coding agents and contributors working in this repository. This is a public repository: never commit credentials, API keys, tokens, or customer data, in code, config, tests, or docs.

Core loop: after completing planned changes, ALWAYS build the affected module before moving on. After changing unit tests, ALWAYS run the changed test classes. Avoid running the whole suite unless necessary.

## Commands

- Format: `make format` (SwiftFormat pinned to `--swiftversion 5.3`, then SwiftLint autofix)
- Lint: `make lint` (SwiftLint `--strict`)
- Generate DI code and mocks: `make generate`, then `make format`, then `make lint`
- Regenerate public API baseline: `./scripts/generate-api-docs.sh` (requires sourcekitten)
- Build one module:
  `xcodebuild -scheme MessagingPushAPN -configuration Debug -workspace ./.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -allowProvisioningUpdates build`
- Build everything: same command with `-scheme Customer.io-Package`

All `make` targets shell out to `./binny`, which is not committed. Install binny first (see `docs/dev-notes/DEVELOPMENT.md`); it downloads the exact tool versions pinned in `binny-tools.yml`. Do not use globally installed sourcery/swiftlint/swiftformat, versions matter.

## Pull Request Requirements (CI will fail otherwise)

1. **PR title must be a conventional commit.** CI lints the title (`lint-pr-title` check). Format: `type(optional-scope): description`, for example `fix(inbox): ...`, `ci: ...`, `chore(geofence): ...`. Breaking changes use `type!: description`. Titles drive semantic-release versioning when squash-merged.
2. **Code must be formatted.** CI runs `make format` and fails on any resulting diff, then runs `make lint`. Run `make format` before every push.
3. **Generated code must be current.** No CI job runs Sourcery for you; stale `*.generated.swift` files show up as compile errors. After changing any protocol marked `AutoMockable` or DI-registered types, run `make generate`.
4. **Public API changes must update the baseline.** The `check-api-breaking-changes` job regenerates `api-docs/*.api` and fails if they differ from what is committed. If you intentionally changed the public API, run `./scripts/generate-api-docs.sh` and commit the updated `api-docs/` files. Unintentional diffs mean you leaked API surface.
5. **Keep SPM and CocoaPods in sync.** Danger warns when `Package.swift` changes without matching `.podspec` changes (or vice versa). A dependency added in one place must be added in both.
6. **Tests must pass.** CI runs the full suite via fastlane scan (scheme `Customer.io-Package`, iPhone 16 simulator) with code coverage uploaded to Codecov.

## Releases and Versioning

- Releases are fully automated with semantic-release from `main` (`beta` and `alpha` are prerelease branches). Conventional commit types decide the bump: `fix` = patch, `feat` = minor, `!` or a BREAKING CHANGE footer = major. Types like `chore`, `ci`, `docs`, `refactor`, `test` do not release.
- NEVER manually edit version numbers. `Sources/Common/Version.swift`, all `.podspec` files, and `CHANGELOG.md` are updated by the release pipeline.
- The SDK ships via both Swift Package Manager and CocoaPods (9 podspecs). Git tags are bare versions (`1.2.3`).

## Code Style

- swift-tools-version is 5.5 and SwiftFormat is pinned to Swift 5.3 idioms; do not use newer language features the pinned tooling cannot handle. CI compiles with a current Xcode toolchain, but source must stay compatible with the pinned tooling.
- Naming: CamelCase for types, camelCase for properties/methods; descriptive method names (`identify`, `registerDeviceToken`)
- Constructor-based dependency injection; use `DIGraphShared` only for top-level module initialization
- Document public APIs with doc comments. Always add doc comments to protocols (public or internal); do not repeat docs on conforming types.
- Error handling: prefer `throws` and `do-try-catch`; use Result only where surrounding code already does
- Avoid force unwrapping (`!`) except in tests
- Prefer `weak` over `unowned`
- Keep types and methods small and single-purpose

## Prohibited Actions

- DO NOT manually edit any `*.generated.swift` file; change the source protocol or template and run `make generate`
- DO NOT expose internal modules to end users (products in `Package.swift` are customer-visible)
- DO NOT modify `Package.swift` unless asked; if you do, mirror the change in the podspecs
- DO NOT manually bump versions, edit `CHANGELOG.md`, or create release tags
- DO NOT commit configuration files with real credentials, and DO NOT put credentials in generated code; always use placeholders
- DO NOT use iOS features unavailable in iOS 13 unless a compatibility fallback is included; call out any post-iOS-13 API you add

## Memory

- In closure capture lists, capture only what is needed, not `self` wholesale
- Use structs for data models; classes only when identity or inheritance is needed; prefer value semantics at API boundaries
- Implement `deinit` cleanup for classes that own resources; cancel async operations in `deinit`
- Document memory ownership expectations in public APIs

## Thread Safety

- Prefer Swift Concurrency over GCD; prefer actors over DispatchQueue unless performance forbids it
- Avoid `sync` GCD operations; call it out explicitly if generated code includes one
- UI work happens on the main thread
- Design with immutability for concurrent code; document the threading model of public APIs
- Include stress tests when testing concurrent code

## Project Structure

- `Sources/` - SDK code by module:
  - `Common/` - shared core (`CioInternalCommon`, internal)
  - `DataPipeline/` - identification and event tracking (`CioDataPipelines`)
  - `MessagingPush/`, `MessagingPushAPN/`, `MessagingPushFCM/` - push messaging
  - `MessagingInApp/` - in-app messaging
  - `Location/` - location and geofencing (`CioLocation`)
  - `Migration/` - upgrade migration tools (`CioTrackingMigration`, internal)
  - `Templates/` - Sourcery templates (`AutoDependencyInjection.stencil`, `AutoMockable.stencil`)
- `Tests/` - tests by module, plus:
  - `Tests/Shared/` - shared test infrastructure (`UnitTestBase`, stubs in `Tests/Shared/Stub`)
  - `Tests/Mocks/<Module>/` - generated mocks, one SPM mock target per module, never shipped to customers
- `Apps/` - sample apps (APN-UIKit, CocoaPods-FCM, and others)
- `api-docs/` - committed public API baseline used by the breaking-change check
- `docs/dev-notes/` - deeper dev docs (development setup, QA, in-app messaging, min versions)

## Architecture

- Each module exposes a public facade extending `ModuleTopLevelObject`; implementation classes stay internal
- Public protocols define interface contracts; builder pattern for configuration

### Initialization pattern

```swift
let config = SDKConfigBuilder(cdpApiKey: "YOUR_CDP_API_KEY")
    .region(.US)
    .build()

CustomerIO.initialize(withConfig: config)
CustomerIO.shared.identify(userId: "customer-id")
```

Optional modules register through the builder before `CustomerIO.initialize(withConfig:)`.

### Dependency injection

- Constructor injection everywhere; `DIGraphShared` is the central registry, used only at module initialization
- Avoid singletons where possible; thread-safe access via Swift Concurrency and the `@Atomic` property wrapper
- Tests substitute components with `diGraphShared.override(value:forType:)`, reset between tests

### Inter-module communication

- Event-based via `EventBus`, type-safe publish/subscribe
- Modules react to events (profile identified, device token registered, etc.) without direct dependencies

## Building and Testing

Before building or testing, list available simulators and pick one (prefer already-booted):

```bash
xcrun simctl list devices available
```

Build for testing once per session or after code changes:

```bash
xcodebuild build-for-testing -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -allowProvisioningUpdates -scheme Customer.io-Package -workspace ./.swiftpm/xcode/package.xcworkspace
```

Run a single test class:

```bash
xcodebuild test-without-building -workspace ./.swiftpm/xcode/package.xcworkspace -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -scheme Customer.io-Package -only-testing:MessagingPushTests/CioProviderAgnosticAppDelegateTests
```

Run a whole suite: drop the `/TestClassName` part.

### Test frameworks

- The suite is mixed: most files use XCTest; newer tests (all of `Tests/Location`, some others) use Swift Testing (`import Testing`).
- Match the framework already used by the file or module you are editing. Base classes (`UnitTestBase`, module `UnitTest` subclasses) are XCTest-based.
- Run tests through `xcodebuild` as shown above, not `swift test`; the Swift Testing tests require a newer swift-tools-version than the manifest declares to run under `swift test`.

### Test structure

- `UnitTestBase<Component>` is the generic base; `UnitTest` is the SDK-wide convenience subclass; modules have their own `UnitTest` subclasses
- Unit tests isolate components with mocks; integration tests extend the same bases with more realistic setup
- Generated mocks (Sourcery, `AutoMockable` protocols) live in `Tests/Mocks/<Module>` and track invocations, arguments, and return values; add mocks to a `MockCollection` for cleanup
- Manual stubs for system interfaces (DeviceInfo, DateUtil, HttpRequestRunner) live in `Tests/Shared/Stub`
- Async helpers: `waitForAsyncOperation`, `runOnBackground`, thread-util stubbing to run async code synchronously
- Name tests `testMethodName_whenCondition_thenResult`; follow Arrange-Act-Assert; keep tests isolated via setup/teardown (`cleanupTestEnvironment()`, `deleteAllPersistentData()`)

## Git Hooks

- Hooks are managed by [lefthook](https://github.com/evilmartians/lefthook), config in `lefthook.yml` (repo root)
- Install: `brew install lefthook && lefthook install`
- pre-commit runs `make format` and re-stages files; pre-push runs `make lint` (warn-only)

## More Documentation

- `docs/dev-notes/DEVELOPMENT.md` - environment setup, binny, codegen
- `docs/dev-notes/` - background queue, event tracking, identity, in-app messaging, minimum OS versions, QA
