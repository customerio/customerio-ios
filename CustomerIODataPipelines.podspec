Pod::Spec.new do |spec|
  spec.name         = "CustomerIODataPipelines"
  spec.version      = "3.5.1" # Don't modify this line - it's automatically updated
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
  spec.ios.deployment_target = "13.0"
  # spec.osx.deployment_target = "10.15"
  # spec.tvos.deployment_target = '13.0'

  path_to_source_for_module = "Sources/DataPipeline"
  spec.source_files = "#{path_to_source_for_module}/**/*{.swift}"
  spec.resource_bundle = {
    "#{spec.module_name}_Privacy" => "#{path_to_source_for_module}/Resources/PrivacyInfo.xcprivacy"
  }
  spec.module_name = "CioDataPipelines" # the `import X` name when using SDK in Swift files
  
  spec.dependency "CustomerIOCommon", "= #{spec.version.to_s}"
  spec.dependency "CustomerIOTrackingMigration", "= #{spec.version.to_s}"

  # Add Segment SDK as a dependency, as this module is designed to be compatible with it.
  spec.dependency 'AnalyticsSwiftCIO', '= 1.5.14+cio.1'
end
