Pod::Spec.new do |spec|
  spec.name         = "CustomerIOLiveActivitiesAttributes"
  spec.version      = "4.7.6" # Don't modify this line - it's automatically updated
  spec.summary      = "Official Customer.io SDK for iOS."
  spec.homepage     = "https://github.com/customerio/customerio-ios"
  spec.documentation_url = 'https://customer.io/docs/sdk/ios/'
  spec.changelog    = "https://github.com/customerio/customerio-ios/blob/#{spec.version.to_s}/CHANGELOG.md"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "CustomerIO Team" => "win@customer.io" }
  spec.source       = { :git => 'https://github.com/customerio/customerio-ios.git', :tag => spec.version.to_s }

  spec.swift_version = '5.9'
  spec.cocoapods_version = '>= 1.11.0'

  spec.platform = :ios
  spec.ios.deployment_target = "13.0"

  # Protocols/models only, no SDK dependency. Safe to import in the app target and the
  # widget extension. Live Activities APIs are @available(iOS 16.2, *)-gated in source.
  path_to_source_for_module = "Sources/LiveActivities_Attributes"
  spec.source_files = "#{path_to_source_for_module}/**/*{.swift}"
  spec.module_name = "CioLiveActivities_Attributes" # the `import X` name when using SDK in Swift files
end
