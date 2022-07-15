#!/bin/sh

# Script that updates the Swift file in the SDK that contains the semantic version of the SDK. 
#
# Designed to be run from CI server or manually. 
# 
# Use script: ./scripts/update-version.sh "0.1.1"

set -e 

NEW_VERSION="$1"
SWIFT_SOURCE_FILE="Sources/Common/Version.swift"

# Given line: `    static let version: String = "0.1.1"` 
# Regex string will match the line of the file that we can then substitute. 
LINE_PATTERN="let version: String = \"\(.*\)\""

echo "Updating file: $SWIFT_SOURCE_FILE to new version: $NEW_VERSION"

# -i overwrites file 
# "s/" means substitute given pattern with given string. 
# 
sed -i "s/$LINE_PATTERN/let version: String = \"$NEW_VERSION\"/" $SWIFT_SOURCE_FILE

echo "Done! New version: "

# print the line (/p) that is matched in the file to show the change. 
sed -n "/$LINE_PATTERN/p" $SWIFT_SOURCE_FILE


echo "Now, updating cocoapods files...."
exec scripts/update-version-cocoapods.sh "$NEW_VERSION"

echo "\n\n Done!\n Dont forget to commit your changes. A good commit message is: \"chore: prepare for $NEW_VERSION\""