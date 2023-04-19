def override_cio_sdk 
  ###
  # How to configure what version of the iOS SDK is installed on your machine. 
  #
  # This is the order of priority for installing:
  # 
  # 1. Install local version of CIO SDK, if the source code is found on your local computer. 
  #    To enable this feature, pass environment variable with the path set to where on your computer the iOS SDK source code is. 
  install_ios_sdk_local_path = ENV['INSTALL_IOS_SDK_LOCAL'] || nil 
  # 2. Install from a CIO SDK git branch. 
  #    To install from a branch, pass environment varible with branch name
  install_ios_sdk_branch_name = ENV['INSTALL_IOS_SDK_BRANCH'] || nil 
  # 3. Install version of CIO SDK specified in `/ios/customer_io.podspec` file. 
  #
  ###

  # All of the CIO pods that are listed as dependencies in `/ios/customer_io.podspec` need to be listed here in this array:
  all_ios_pods_sdk_wrapper_needs = [
    'CustomerIOCommon',
    'CustomerIOTracking',
    'CustomerIOMessagingInApp',
    'CustomerIOMessagingPush',
    'CustomerIOMessagingPushAPN'
  ]

  if install_ios_sdk_local_path != nil then 
    puts ""
    puts "⚠️ Installing local version of the iOS SDK. Path of iOS SDK: #{install_ios_sdk_local_path}"
    puts ""

    all_ios_pods_sdk_wrapper_needs.each { |podname| 
      pod podname, :path => install_ios_sdk_local_path
    }

    return true 
  elsif install_ios_sdk_branch_name != nil then 
    puts ""
    puts "⚠️ Installing CIO iOS SDK from git branch #{install_ios_sdk_branch_name}"
    puts ""

    all_ios_pods_sdk_wrapper_needs.each { |podname| 
      pod podname, :git => "https://github.com/customerio/customerio-ios.git", :branch => install_ios_sdk_branch_name
    }

    return true 
  end 

  return false 
end 