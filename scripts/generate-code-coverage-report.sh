#!/bin/sh

# After tests have been executed, we need to generate a file with the code 
# coverage statistics in it. This file will then be what we upload to a 
# code coverage service suh as CodeCov.io 
# This means that it's important that we generate a code coverage report that 
# the service we are using supports. 
#
# Use script: generate-code-coverage-report.sh ".build" "CioTracking,CioMessagingPushAPN,CioMessagingPushFCM,Common,"
# first argument is the directory you want all generated files to go into. 
# second argument is a comma separated list of targets that you want code coverage for. This includes common modules that are used internally. Make sure to have a trailing ',' in the string! 
# 
# The final report that you should be uploading will be 1 file in directory: .build/generated/

set -e

OUTPUT_DIR="$1"
LIST_TARGETS="$2"

# Install some tools that we need 
# mint allows us to execute a swift package manager executable
brew install mint

# We use Apple's xccov tool to take .xcresult/ and parse the code coverage report from that data. 
# We generate a json file with all the code coverage content in it. 
XCODE_CODE_COV_REPORT="$OUTPUT_DIR/code-coverage.json"
echo "Parsing .xcresult/ for code coverage to $XCODE_CODE_COV_REPORT"
xcrun xccov view --report *.xcresult --json > "$XCODE_CODE_COV_REPORT"

# Takes the newline separated string and turns it into a single line string separated by spaces and adds another space to the very end: Example: 'foo foo foo ' 
# Then, sed command uses regex to turn 'foo bar ' into '--include-targets foo --include-targets bar'. 
TARGETS=$(echo "$LIST_TARGETS" | sed 's/\([A-Za-z0-9]*\),/--include-targets \1 /g')
echo "Include targets command line argument: "
echo "\n\nExpected value of variable: a string with format: '--include-targets foo --include-targets bar'"
echo "Actual value: $TARGETS"
echo "\n\n"

# Run tool https://github.com/trax-retail/xccov2lcov to generate lcov file from 
# We need a lcov file because codecov.io does not understand the xccov file that Apple geneated. 
echo "Generating lcov report from json"
LCOV_REPORT="$OUTPUT_DIR/generated/code-coverage.info"
mkdir -p "$OUTPUT_DIR/generated"
mint run trax-retail/xccov2lcov@master "$XCODE_CODE_COV_REPORT" --trim-path $(pwd) $TARGETS > "$LCOV_REPORT"
echo "Generated lcov report to $LCOV_REPORT"


