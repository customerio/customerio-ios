Pod::Spec.new do |spec|
    spec.name         = "SampleAppsCommon"
    spec.version      = "1.0.0" 
    spec.summary      = "Common components for Customer.io iOS SDK sample apps"
    spec.homepage     = "https://github.com/customerio/customerio-ios"  
    spec.author       = { "CustomerIO Team" => "win@customer.io" }
    spec.source       = { :git => '', :tag => "" }
  
    spec.source_files  = "Source/**/*.{swift}"
    spec.resources     = "Source/Assets/**/*"
    
    # Dependencies for all Customer.io modules
    spec.dependency "CustomerIODataPipelines"
    spec.dependency "CustomerIOMessagingPushAPN"
    spec.dependency "CustomerIOMessagingPushFCM"
    spec.dependency "CustomerIOMessagingInApp"
    
    spec.ios.deployment_target = "13.0"
    spec.swift_version = "5.3"
    
    # Ensure all subdirectories are included
    spec.subspec 'Manager' do |ss|
        ss.source_files = 'Source/Manager/**/*.{swift}'
    end
    
    spec.subspec 'Model' do |ss|
        ss.source_files = 'Source/Model/**/*.{swift}'
    end
    
    spec.subspec 'Store' do |ss|
        ss.source_files = 'Source/Store/**/*.{swift}'
    end
    
    spec.subspec 'View' do |ss|
        ss.source_files = 'Source/View/**/*.{swift}'
    end
    
    spec.subspec 'Router' do |ss|
        ss.source_files = 'Source/Router/**/*.{swift}'
    end
    
    spec.subspec 'Service' do |ss|
        ss.source_files = 'Source/Service/**/*.{swift}'
    end
    
    spec.subspec 'Util' do |ss|
        ss.source_files = 'Source/Util/**/*.{swift}'
    end
  end