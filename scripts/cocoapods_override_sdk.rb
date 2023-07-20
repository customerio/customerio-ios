# This is a Ruby file designed to be used by our SDK wrapper sample apps if they want to install 
# a non-production build of the iOS native SDK. 
# 
# Here is an example Podfile showing you how to use this script: 
=begin

# Import Ruby functions from native SDK to more easily allow installing non-production SDK builds. 
require 'open-uri'
IO.copy_stream(URI.open('https://raw.githubusercontent.com/customerio/customerio-ios/main/scripts/cocoapods_override_sdk.rb'), "/tmp/override_cio_sdk.rb")
load "/tmp/override_cio_sdk.rb"

# Required by native iOS FCM SDK. 
# Uncomment the line below if you are installing any of the FCM CIO pods. 
# use_frameworks! :linkage => :static

target 'SampleApp' do
  # Uncomment only 1 of the lines below to install a version of the iOS SDK 
  pod 'CustomerIO/MessagingPushAPN', '~> 2.1' # install production build 
  # install_non_production_ios_sdk_local_path(local_path: '~/code/customerio-ios/', is_app_extension: false, push_service: "apn")
  # install_non_production_ios_sdk_git_branch(branch_name: 'name-of-ios-sdk-branch', is_app_extension: false, push_service: "fcm")
end

target 'Notification Service' do
  # Uncomment only 1 of the lines below to install a version of the iOS SDK 
  pod 'CustomerIO/MessagingPushAPN', '~> 2.1' # install production build 
  # install_non_production_ios_sdk_local_path(local_path: '~/code/customerio-ios/', is_app_extension: true, push_service: "apn")
  # install_non_production_ios_sdk_git_branch(branch_name: 'name-of-ios-sdk-branch', is_app_extension: true, push_service: "fcm")
end

=end 

def install_non_production_ios_sdk_git_branch(branch_name:, is_app_extension:, push_service:)
  puts ""
  puts "⚠️ Installing CIO iOS SDK from git branch #{branch_name}"
  puts ""

  get_all_cio_pods(is_app_extension, push_service).each { |podname| 
    pod podname, :git => "https://github.com/customerio/customerio-ios.git", :branch => branch_name
  }  
end 

def install_non_production_ios_sdk_local_path(local_path:, is_app_extension:, push_service:)
  local_path = File.expand_path(local_path, Dir.pwd)

  puts ""
  puts "⚠️ Installing local version of the iOS SDK. Path of iOS SDK: #{local_path}"
  puts ""

  get_all_cio_pods(is_app_extension, push_service).each { |podname| 
    pod podname, :path => local_path
  }
end 

# In iOS App Extensions (example: Notification Service Extensions for rich push), there are some pods we do not want to install. If we do, it might cause our app to no longer compile. 
def get_all_cio_pods(is_app_extension, push_service)
  # All of these pods are App Extension compatible. We can install them all in an App Extension or a host app. 
  pods_for_all_targets = [
    'CustomerIOCommon',
    'CustomerIOTracking',    
    'CustomerIOMessagingPush'
  ]

  if push_service == "apn" 
    pods_for_all_targets.push('CustomerIOMessagingPushAPN')
  end 

  # native iOS FCM SDK requires that you add this to your Podfile...
  # use_frameworks! :linkage => :static 
  # ...For apps that only use APN, we do not want to modify the Podfile to not cause your pod install to break. 
  # Therefore, only install the FCM pod if you need it for your app. 
  if push_service == "fcm"
    pods_for_all_targets.push('CustomerIOMessagingPushFCM') 
  end 

  if !is_app_extension     
    # Gist SDK is not setup to work with App Extensions. Therefore, only install it if we are not in an App extension. 
    pods_for_all_targets.push('CustomerIOMessagingInApp')
  end 

  return pods_for_all_targets
end 
