Pod::Spec.new do |spec|
  spec.name         = "SampleAppsCommon"
  spec.version      = "1.0.0" 
  spec.summary      = "---"
  spec.homepage     = "https://github.com/customerio/customerio-ios"  
  spec.author       = { "CustomerIO Team" => "win@customer.io" }
  spec.source       = { :git => '', :tag => "" }

  spec.source_files  = "Source/**/*"
  spec.dependency "CustomerIOTracking"
  spec.ios.deployment_target = "13.0"
end