Pod::Spec.new do |spec|
  spec.name         = "CustomerIO"
  spec.version      = "1.0.0-alpha.21" # DONT MODIFY LINE, it's automatically updated -- auto-update-version
  spec.summary      = "Official Customer.io SDK for iOS."
  spec.description  = <<-DESC
  Official Customer.io SDK for iOS. Track customers and send messages to your iOS app. 
                   DESC
  spec.homepage     = "https://github.com/customerio/customerio-ios"
  spec.documentation_url = 'https://customer.io/docs/sdk/ios/'
  spec.changelog = "https://github.com/customerio/customerio-ios/blob/alpha/CHANGELOG.md"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "CustomerIO Team" => "win@customer.io" }
  spec.source = { :git => 'https://github.com/customerio/customerio-ios.git', :tag => spec.version.to_s }

  spec.swift_version = '5.3'
  spec.cocoapods_version = '>= 1.11.0'

  spec.platform = :ios # platforms SDK supports. Leave blank and it's assumed SDK supports all platforms. 
  spec.ios.deployment_target = "13.0"
  # spec.osx.deployment_target = "10.15"
  # spec.tvos.deployment_target = '13.0'

  spec.default_subspec = "Tracking"

  spec.subspec "Tracking" do |ss|
    ss.dependency "CustomerIOTracking"
  end

  spec.subspec "MessagingPush" do |ss|
    ss.dependency "CustomerIOMessagingPush"
  end

  spec.subspec "MessagingPushAPN" do |ss|
    ss.dependency "CustomerIOMessagingPushAPN"
  end

  spec.subspec "MessagingPushFCM" do |ss|
    ss.dependency "CustomerIOMessagingPushFCM"
  end
end