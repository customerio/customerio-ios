# NOTE: This module is in development and not yet published to CocoaPods trunk.
# It will be published when the Location module is ready for customers.

Pod::Spec.new do |spec|
  spec.name         = "CustomerIOLocation"
  spec.version      = "4.1.2" # Don't modify this line - it's automatically updated
  spec.summary      = "Official Customer.io SDK for iOS - Location Module."
  spec.homepage     = "https://github.com/customerio/customerio-ios"
  spec.documentation_url = 'https://customer.io/docs/sdk/ios/'
  spec.changelog    = "https://github.com/customerio/customerio-ios/blob/#{spec.version.to_s}/CHANGELOG.md"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "CustomerIO Team" => "win@customer.io" }
  spec.source       = { :git => 'https://github.com/customerio/customerio-ios.git', :tag => spec.version.to_s }

  spec.swift_version = '5.3'
  spec.cocoapods_version = '>= 1.11.0'

  spec.platform = :ios
  spec.ios.deployment_target = "13.0"

  path_to_source_for_module = "Sources/Location"
  spec.source_files = "#{path_to_source_for_module}/**/*{.swift}"
  spec.resource_bundle = {
    "#{spec.module_name}_Privacy" => "#{path_to_source_for_module}/Resources/PrivacyInfo.xcprivacy"
  }

  spec.module_name = "CioLocation"

  spec.dependency "CustomerIOCommon", "= #{spec.version.to_s}"
 end
