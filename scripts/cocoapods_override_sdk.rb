# This is a Ruby file designed to be used by our SDK wrapper sample apps if they want to install 
# a non-production build of the iOS native SDK. 
# 
# Here is an example Podfile showing you how to use this script: 
=begin

# Import Ruby functions from native SDK to more easily allow installing non-production SDK builds. 
require 'open-uri'
IO.copy_stream(URI.open('https://raw.githubusercontent.com/customerio/customerio-ios/main/scripts/cocoapods_override_sdk.rb'), "/tmp/override_cio_sdk.rb")
load "/tmp/override_cio_sdk.rb"

target 'SampleApp' do
  # Uncomment only 1 of the lines below to install a version of the iOS SDK 
  pod 'CustomerIO/MessagingPushAPN', '~> 2.1' # install production build 
  # install_non_production_ios_sdk_local_path('~/code/customerio-ios/')
  # install_non_production_ios_sdk_git_branch('name-of-ios-sdk-branch')
end

target 'Notification Service' do
  # Uncomment only 1 of the lines below to install a version of the iOS SDK 
  pod 'CustomerIO/MessagingPushAPN', '~> 2.1' # install production build 
  # install_non_production_ios_sdk_local_path('~/code/customerio-ios/')
  # install_non_production_ios_sdk_git_branch('name-of-ios-sdk-branch')
end

=end 

def install_non_production_ios_sdk_git_branch(branch_name)
  puts ""
  puts "⚠️ Installing CIO iOS SDK from git branch #{branch_name}"
  puts ""

  get_all_cio_pods.each { |podname| 
    pod podname, :git => "https://github.com/customerio/customerio-ios.git", :branch => branch_name
  }  
end 

def install_non_production_ios_sdk_local_path(local_path)
  local_path = File.expand_path(local_path, Dir.pwd)

  puts ""
  puts "⚠️ Installing local version of the iOS SDK. Path of iOS SDK: #{local_path}"
  puts ""

  get_all_cio_pods.each { |podname| 
    pod podname, :path => local_path
  }
end 

def get_all_cio_pods
  return [
    'CustomerIOCommon',
    'CustomerIOTracking',
    'CustomerIOMessagingInApp',
    'CustomerIOMessagingPush',
    'CustomerIOMessagingPushAPN',
    'CustomerIOMessagingPushFCM'
  ]
end 