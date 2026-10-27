# Firebase adapter for MessagingPushFCM. Until SDK 5.0.0 this pod was published from customerio/customerio-ios-fcm (1.0.x).
# It keeps the pod and module name, so CocoaPods installs either the old wrapper or this one, never both.

Pod::Spec.new do |spec|
  spec.name         = "CioFirebaseWrapper"
  spec.version      = "5.1.0" # Don't modify this line - it's automatically updated
  spec.summary      = "Official Customer.io SDK for iOS."
  spec.homepage     = "https://github.com/customerio/customerio-ios"
  spec.documentation_url = 'https://customer.io/docs/sdk/ios/'
  spec.changelog    = "https://github.com/customerio/customerio-ios/blob/#{spec.version.to_s}/CHANGELOG.md"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "CustomerIO Team" => "win@customer.io" }
  spec.source       = { :git => 'https://github.com/customerio/customerio-ios.git', :tag => spec.version.to_s }

  spec.swift_version = '5.3'
  spec.cocoapods_version = '>= 1.11.0'

  spec.platform = :ios # platforms SDK supports. Leave blank and it's assumed SDK supports all platforms.
  spec.ios.deployment_target = "15.0"

  spec.module_name = "CioFirebaseWrapper" # the `import X` name when using SDK in Swift files

  # The default installs FirebaseMessaging from CocoaPods, as the old wrapper did.
  spec.default_subspec = "FirebaseMessaging"

  # The adapter alone. It finds FirebaseMessaging at runtime, so apps that get Firebase another way (for example
  # Firebase 13, which only ships through SwiftPM) can use `pod 'CioFirebaseWrapper/Core'`.
  spec.subspec "Core" do |ss|
    ss.source_files = "Sources/FirebaseWrapper/**/*{.swift}"
    ss.dependency "CustomerIOMessagingPushFCM", "= #{spec.version.to_s}"
  end

  spec.subspec "FirebaseMessaging" do |ss|
    ss.dependency "CioFirebaseWrapper/Core"
    # Firebase 13 isn't published to CocoaPods; the upper bound admits it if it ever is.
    ss.dependency "FirebaseMessaging", ">= 8.7.0", "< 14.0.0"
  end
end
