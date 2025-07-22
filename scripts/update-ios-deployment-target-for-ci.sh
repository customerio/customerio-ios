#!/bin/bash

# Script to temporarily update iOS deployment target in Package.swift for CI testing
# 
# Context: Firebase 12+ requires iOS 15+ minimum deployment target, but our SDK supports iOS 13+.
# This script allows CI to run tests with iOS 15+ while keeping SDK's public API at iOS 13+.
# 
# This script:
# 1. Validates that Package.swift currently has exactly ".iOS(.v13)" 
# 2. Temporarily updates it to ".iOS(.v15)" for CI testing
# 3. Fails if the current value is anything other than ".iOS(.v13)" to prevent accidental changes
#
# Usage: ./scripts/update-ios-deployment-target-for-ci.sh

set -e  # Exit on any error

PACKAGE_SWIFT="Package.swift"
EXPECTED_CURRENT=".iOS(.v13)"
NEW_TARGET=".iOS(.v15)"
# Escape special regex characters for sd
EXPECTED_CURRENT_ESCAPED="\.iOS\(\.v13\)"
# Escaped new target is the same as the new target since it doesn't need escaping
NEW_TARGET_ESCAPED="$NEW_TARGET"

echo "🔍 Checking current iOS deployment target in Package.swift..."

# Check if Package.swift exists
if [[ ! -f "$PACKAGE_SWIFT" ]]; then
    echo "❌ Error: Package.swift not found!"
    exit 1
fi

# Check if the expected pattern exists
if ! grep -q "platforms: \[" "$PACKAGE_SWIFT"; then
    echo "❌ Error: Could not find 'platforms: [' in Package.swift"
    exit 1
fi

# Extract the current iOS deployment target
CURRENT_TARGET=$(grep -A 2 "platforms: \[" "$PACKAGE_SWIFT" | grep "\.iOS" | xargs)

echo "📋 Current iOS deployment target: $CURRENT_TARGET"

# Validate that current target is exactly what we expect
if [[ "$CURRENT_TARGET" != "$EXPECTED_CURRENT" ]]; then
    echo "❌ Error: Expected iOS deployment target to be '$EXPECTED_CURRENT' but found '$CURRENT_TARGET'"
    echo ""
    echo "This script only works when the deployment target is exactly '$EXPECTED_CURRENT'."
    echo "If you've intentionally changed the deployment target, please update this script accordingly."
    echo "This safeguard prevents accidental modification of Package.swift."
    exit 1
fi

echo "✅ Current target matches expected value"
echo "🔄 Updating iOS deployment target from $EXPECTED_CURRENT to $NEW_TARGET for CI testing..."

# Perform the replacement using sd with escaped regex
sd "$EXPECTED_CURRENT_ESCAPED" "$NEW_TARGET_ESCAPED" "$PACKAGE_SWIFT"

# Verify the change was made
if grep -q "$NEW_TARGET" "$PACKAGE_SWIFT"; then
    echo "✅ Successfully updated iOS deployment target to $NEW_TARGET"
    
    # Show the change for verification
    echo ""
    echo "📋 Updated platforms section:"
    grep -A 3 "platforms: \[" "$PACKAGE_SWIFT"
else
    echo "❌ Error: Failed to update iOS deployment target"
    exit 1
fi

echo ""
echo "🎯 iOS deployment target temporarily updated for CI testing"
echo "⚠️  Remember: This change is only for CI testing Firebase 12+ compatibility"
echo "⚠️  The SDK still supports iOS 13+ for end users"
