#!/bin/sh

# Updates all of the cocoapods files with the latest version of the SDK to publish
# 
# Use script: ./scripts/update-version-cocoapods.sh 0.1.1 

set -e 

NEW_VERSION="$1"

# Given line: `    static let version: String = "0.1.1"` 
# Regex string will match the line of the file that we can then substitute. 
LINE_PATTERN="spec.version\s*=.*"

for PODSPEC_FILE in ./*.podspec; do
    echo "Updating file: $PODSPEC_FILE to new version: $NEW_VERSION"

    # Uses CLI: https://github.com/chmln/sd to replace values inside of file
    sd "$LINE_PATTERN" "spec.version      = \"$NEW_VERSION\" # Don't modify this line - it's automatically updated" $PODSPEC_FILE

    echo "Done! Showing changes to confirm it worked: "

    git diff $PODSPEC_FILE
done