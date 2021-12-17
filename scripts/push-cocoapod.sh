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

set -e 

PODSPEC="$1"

if ! [[ -f "$PODSPEC" ]]; then
    echo "File $PODSPEC does not exist. Please check the pod name."
fi

echo "Pushing podspec: $PODSPEC."

for i in {1..30}; do 
    echo "Push attempt $i..."
    pod repo update;
    pod trunk push "$PODSPEC" --allow-warnings && break || sleep 30; 
    echo "Failed to push. Sleeping, then will try again."
done