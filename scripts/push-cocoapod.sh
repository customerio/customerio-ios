#!/bin/sh

set -e # fail script if an error is encountered 

# Pushes a given Cocoapod to the Cocoapods server for deployment. 
# Use script: ./scripts/push-cocoapod.sh CustomerIO.podspec

# We have cocoapods that depend on other cocoapods that we publish.
# Example: 
# Push - CustomerIODataPipelines version 1.1.1
# Push - CustomerIOMessagingPush version 1.1.1
# Pushing MessagingPush will fail because when you push a Cocoapod, the server you pushed to (the CDN)
# Takes a few minutes to refresh. Pushing the cocoapod will fail because it will say that 
# it cannot find the Tracking SDK version 1.1.1. 
# 
# To fix this issue, we use the --synchronous option when pushing. This uses the old (and slow) method of deploying 
# cocoapods using a git repo. 
# Learn more: https://github.com/CocoaPods/CocoaPods/issues/9497 

PODSPEC="$1"

if ! [[ -f "$PODSPEC" ]]; then
    echo "File $PODSPEC does not exist. Please check the pod name."
    exit 1
fi

echo "Pushing podspec: $PODSPEC."
echo "If a pod version has already been published, it will be treated as success."
echo "For any other failure, the script will exit with a non-zero code."

OUTPUT=$(pod trunk push "$PODSPEC" --allow-warnings --synchronous 2>&1) || true
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "successfully published"; then
  echo "Pod $PODSPEC published successfully."
  exit 0
elif echo "$OUTPUT" | grep -q "Unable to accept duplicate entry for"; then
  echo "Pod $PODSPEC has already been published. Skipping."
  exit 0
else
  echo "::error::Failed to push $PODSPEC."
  exit 1
fi
