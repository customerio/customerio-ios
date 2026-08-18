Pod::Spec.new do |spec|
  spec.name         = "CustomerIOLiveActivities"
  spec.version      = "4.7.4" # Don't modify this line - it's automatically updated
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

  # Live Activities runtime (registration, lifecycle, delivery/token reporting). Import in the
  # app target only. Live Activities APIs are @available(iOS 16.2, *)-gated in source.
  path_to_source_for_module = "Sources/LiveActivities"
  spec.source_files = "#{path_to_source_for_module}/**/*{.swift}"
  spec.module_name = "CioLiveActivities" # the `import X` name when using SDK in Swift files

  spec.dependency "CustomerIOCommon", "= #{spec.version.to_s}"
  spec.dependency "CustomerIOLiveActivitiesAttributes", "= #{spec.version.to_s}"
end
