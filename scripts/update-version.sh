#!/bin/sh

# Script that updates the Swift file in the SDK that contains the semantic version of the SDK. 
#
# Designed to be run from CI server or manually. 
# 
# Use script: ./scripts/update-version.sh "0.1.1"

set -e 

NEW_VERSION="$1"

RELATIVE_PATH_TO_SCRIPTS_DIR=$(dirname "$0")
ABSOLUTE_PATH_TO_SOURCE_CODE_ROOT_DIR=$(realpath "$RELATIVE_PATH_TO_SCRIPTS_DIR/..")
SWIFT_SOURCE_FILE="$ABSOLUTE_PATH_TO_SOURCE_CODE_ROOT_DIR/Sources/Common/Version.swift"

echo "Updating file: $SWIFT_SOURCE_FILE to new version: $NEW_VERSION"

# Uses CLI tool sd to replace string in a file: https://github.com/chmln/sd
# Given line: `    public static let version: String = "0.1.1"` 
# Regex string will match the line of the file that we can then substitute. 
sd "let version: String = \"(.*)\"" "let version: String = \"$NEW_VERSION\"" $SWIFT_SOURCE_FILE

echo "Done! Showing changes to confirm it worked: "
git diff $SWIFT_SOURCE_FILE
