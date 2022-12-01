#!/bin/sh

# Pushes a given Cocoapod to the Cocoapods server for deployment. 
# Use script: ./scripts/push-cocoapod.sh CustomerIO.podspec

# We have cocoapods that depend on other cocoapods that we publish.
# Example: 
# Push - CustomerIOTracking version 1.1.1
# Push - CustomerIOMessagingPush version 1.1.1, depends on CustomerIOTracking 1.1.1
# Pushing MessagingPush will fail because when you push a Cocoapod, the server you pushed to (the CDN)
# Takes a few minutes to refresh. Pushing the cocoapod will fail because it will say that 
# it cannot find the Tracking SDK version 1.1.1. 
# 
# To fix this issue, we have a couple of options:
# 1. Sleep and retry. 
# 2. Instead of using the CDN server, use the old git repo as the "server". 
#    Learn more: https://github.com/CocoaPods/CocoaPods/issues/9497 
# Option 1 has been chosen because from using Cocoapods in the past, the CDN is more stable 
# then using the git repo. We *might* save a couple minutes here and there when using the git repo
# but we will potentially need to deal with more failed deployments. 

PODSPEC="$1"
NUMBER_RETRIES=60
PUSH_SUCCESS="false"

if ! [[ -f "$PODSPEC" ]]; then
    echo "File $PODSPEC does not exist. Please check the pod name."
fi

echo "Pushing podspec: $PODSPEC."

for i in $(seq 1 $NUMBER_RETRIES); do 
    if [[ $PUSH_SUCCESS == "false" ]]; then
        echo "Push attempt $i..."
        pod repo update;
        # if the push is successful, it will set PUSH_SUCCESS which will prevent from trying to push again. Else, sleep 30 seconds and try again. 
        pod trunk push "$PODSPEC" --allow-warnings --synchronous && PUSH_SUCCESS="true" || sleep 30;
        echo "Failed to push. Sleeping, then will try again."

        if [ $i -eq $NUMBER_RETRIES ]; then 
            echo "Hit retry limit. Failed to push the pod $PODSPEC. Exiting script with failure status."
            echo "Currently not existing script if timeout because we allow you to run deploy script manually and you cannot overwrite existing pods. It's best to check emails saying that pod got deployed or https://github.com/cocoaPods/specs to see if pod got pushed."
            # exit 1 
        fi 
    fi 
done