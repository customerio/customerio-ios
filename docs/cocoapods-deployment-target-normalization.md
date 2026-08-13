# CocoaPods deployment-target normalization

Xcode validates the deployment target of every target in `Pods.xcodeproj`, including dependency,
aggregate, privacy-manifest, and resource-bundle targets. A dependency can support your app's iOS
version at runtime while its generated target still carries older deployment metadata. Xcode 27
rejects those generated targets when they are below the SDK's supported build range.

Customer.io provides an opt-in Podfile helper that raises low or missing generated target settings
to iOS 15.0. It also covers CocoaPods-integrated app, Notification Service Extension, and widget
targets, while preserving any numeric deployment target already above 15.0. When a target setting
is absent, the helper resolves its target xcconfig and then the same-named project build
configuration, so a higher inherited app or extension floor is not replaced with 15.0. The helper
changes local build settings in the generated Pods project and CocoaPods-integrated app or
extension projects. It does not rewrite a podspec, change an SDK's public platform declaration, or
make an API available on an older OS.

Customer.io deliberately continues to publish SDKs that support iOS versions below 15. A podspec
can therefore correctly declare that lower library minimum even when the application consuming it
has moved to iOS 15 or later. CocoaPods carries deployment metadata from Customer.io and
third-party podspecs into generated build targets, but Xcode 27 no longer accepts targets below the
iOS SDK's supported build range. Raising every published podspec to iOS 15 would unnecessarily
drop older applications and would not control metadata from transitive dependencies. The helper
instead aligns the generated targets with the host application's chosen minimum while leaving the
SDK's published runtime compatibility unchanged. This is the supported integration policy for an
application that has moved its own minimum to iOS 15 or later.

> [!WARNING]
> This is an opt-in build migration, not a way to keep an iOS 13 or iOS 14 application floor.
> Integrated app and extension targets below iOS 15.0 are raised to 15.0. Shipping that project
> means users on iOS 13 or iOS 14 cannot install subsequent app updates. Adopt the helper only when
> your product has intentionally moved its application and extension deployment targets to iOS 15.

## Add the helper

1. Copy [`scripts/cocoapods_deployment_target.rb`](../scripts/cocoapods_deployment_target.rb) into
   the directory containing your `Podfile`, keeping the filename `cocoapods_deployment_target.rb`.
   Use the file from the same Customer.io SDK release tag that your app consumes so the integration
   is reproducible.
2. Load it near the top of your `Podfile`.
3. Call it at the end of your existing `post_install` block. A Podfile can have only one
   `post_install` block, so keep CocoaPods, Flutter, or React Native's existing hook calls before
   the Customer.io call.

```ruby
require_relative 'cocoapods_deployment_target'

platform :ios, '15.0'

# targets and pods...

post_install do |installer|
  # Keep any existing post-install setup here first.

  CustomerIO::CocoaPodsDeploymentTarget.normalize!(
    installer,
    minimum_ios_version: '15.0'
  )
end
```

Run a clean install after changing the Podfile:

```sh
rm -rf Pods
bundle exec pod install --repo-update
```

The helper resolves target xcconfig settings and the matching project configuration before adding a
target override. For each change, it prints a stable project, target, and configuration line with
the original effective value and final value. It fails the install if the selected effective value
is non-numeric, such as `$(CUSTOM_IOS_FLOOR)`, because a generated-project audit cannot prove the
resolved value. A non-numeric value at a lower precedence does not fail when an explicit numeric
target setting already determines the effective value.

If an error says an xcconfig cannot be read or parsed, repair or remove the reported base
configuration file reference for the reported project, target, and configuration. Run the helper
in the CocoaPods Ruby environment so the public `Xcodeproj::Config` parser is available.
Synchronized-group xcconfig references are not resolved by that public parser; if the helper
reports one, replace it with a standard xcconfig file reference, then run `pod install` again.
These cases fail before any project mutation.

## When the helper is no longer needed

Keep the helper while a supported dependency graph can validly include deployment metadata below
the host application's minimum. This is expected while Customer.io supports older iOS versions or
supported third-party pods continue to declare lower minimums. A `platform` declaration in the
application's Podfile alone does not guarantee that every generated target uses the same value.

The helper becomes unnecessary only when a clean install without it proves that every
target/configuration in every supported resolved dependency graph declares an effective numeric
deployment target at or above the host application's minimum. That state would normally follow an
intentional platform-support change across the SDK, wrappers, and relevant dependencies; it is not
a prerequisite for adopting Xcode 27. Keep the standalone audit in CI after removing the helper so
a later dependency update cannot silently reintroduce a lower target.

## Audit the generated projects

The standalone audit prints the target, matching project, and effective value for every
target/configuration pair in a stable order. It exits nonzero if any effective value is missing,
non-numeric, or below the requested minimum. Pass the `Pods` directory and each integrated
application project so app and extension targets are included. The audit recursively discovers
every `.xcodeproj` under `Pods`, including CocoaPods multi-project output, and fails if a supplied
path is missing or contains no projects. The audit examines every target in each passed
project, including non-integrated targets that the normalizer intentionally does not change; set
those targets to the host minimum explicitly.

```sh
bundle exec ruby scripts/audit_cocoapods_deployment_targets.rb \
  --minimum 15.0 \
  Pods \
  YourApp.xcodeproj
```

The repository's native CocoaPods report is produced by `CocoaPods-FCM`. Its resolved graph also
contains the APN-based Rich Push Notification Service Extension and Live Activity widget targets.
`APN-UIKit` has no `Podfile` or generated Pods graph, so the shared action intentionally skips this
audit for that sample and validates its Swift Package Manager build separately. It is not an APN
CocoaPods audit.

Keep the audit in CI next to the simulator build and unsigned generic-device archive. A successful
audit and build do not prove real-device push delivery, signed archive export, or App Store
submission.
