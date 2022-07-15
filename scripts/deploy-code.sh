#!/bin/bash

# This file exists 

set -e

if [[ "$COCOAPODS_TRUNK_TOKEN" == "" ]]; then # makes sure deployment key set. 
    echo "Forgot to set environment variable COCOAPODS_TRUNK_TOKEN (value found in 1password for cocoapods ios sdk). Set it, then try again."
    echo "Set variable with command (yes, with the double quotes around the variable value): export NAME_OF_VAR=\"foo\""
    exit 1
fi 

if [[ "$CI" == "" ]]; then # manual deployment 
    echo "The iOS SDK is deployed in 2 places: Swift Package Manager (SPM) and Cocoapods."
    echo "For SPM, we just need to create a git tag which we have already done so that part is done!"
    echo "So, time to deploy the code to cocoapods."
    echo "Note: This can take up to a couple of hours to complete. You can instead run this script on the CI server by going to: https://github.com/customerio/customerio-ios/actions/workflows/deploy-cocoapods.yml > typing in the semantic version of the release to deploy > Run workflow."
    echo "Hit ENTER key to continue running the script or Ctrl+C to cancel."

    read # waits for ENTER key to be pressed to continue.     
fi 

echo "Push CustomerIOTracking"
exec ./scripts/push-cocoapod.sh CustomerIOTracking.podspec

echo "Push CustomerIOMessagingPush"
exec ./scripts/push-cocoapod.sh CustomerIOMessagingPush.podspec

echo "Push CustomerIOMessagingPushAPN"
exec ./scripts/push-cocoapod.sh CustomerIOMessagingPushAPN.podspec

echo "Push CustomerIOMessagingPushFCM"
exec ./scripts/push-cocoapod.sh CustomerIOMessagingPushFCM.podspec

echo "Push CustomerIO"
exec ./scripts/push-cocoapod.sh CustomerIO.podspec

