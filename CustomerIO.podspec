# Cocoapods projects that provide multiple SDKs have a common naming pattern for installing pods:
# CustomerIO/Tracking 
# This podspec allows that. It publishes aliases for the cocoapods we have already published. 
# Example: CustomerIO/Tracking is an alias for the published pod CustomerIOTracking

Pod::Spec.new do |spec|
  spec.name         = "CustomerIO"
  spec.version      = "1.2.5" # Don't modify this line - it's automatically updated
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

  spec.default_subspec = "Tracking"

  spec.subspec "Common" do |ss|
    ss.source_files  = "Sources/Common/**/*"
    ss.module_name = "Common" # the `import X` name when using SDK in Swift files
  end

  spec.subspec "Tracking" do |ss|
    ss.source_files  = "Sources/Tracking/**/*"
    ss.module_name = "CioTracking" # the `import X` name when using SDK in Swift files  
    ss.dependency "CustomerIO/Common"
  end

  spec.subspec "MessagingPush" do |ss|
    ss.source_files  = "Sources/MessagingPush/**/*"
    ss.module_name = "CioMessagingPush"  # the `import X` name when using SDK in Swift files
    ss.dependency "CustomerIO/Tracking"
  end

  spec.subspec "MessagingPushAPN" do |ss|
    ss.source_files  = "Sources/MessagingPushAPN/**/*"
    ss.module_name = "CioMessagingPushAPN" # the `import X` name when using SDK in Swift files  
    ss.dependency "CustomerIO/MessagingPush"
  end

  spec.subspec "MessagingPushFCM" do |ss|
    ss.source_files  = "Sources/MessagingPushFCM/**/*"
    ss.module_name = "CioMessagingPushFCM" # the `import X` name when using SDK in Swift files   
    ss.dependency "CustomerIO/MessagingPush"
  end

  spec.subspec "MessagingInApp" do |ss|
    ss.source_files  = "Sources/MessagingInApp/**/*"
    ss.module_name = "CioMessagingInApp"  # the `import X` name when using SDK in Swift files    
    ss.dependency "CustomerIO/Tracking"
    ss.dependency "Gist", '~> 2.2.1'
  end
end