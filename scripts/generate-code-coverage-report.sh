#!/bin/sh

# In order for us to view the code coverage of our project, we need a few things. 
# 1. Run tests to determine the test coverage of the project. 
# 2. Generate a file that tells you the test coverage of your project. 
# 3. (Optional) Upload this generated file to a service such as CodeCov.io which tells you 
# historical data on the test coverage of your project. 
#
# This script takes care of item #2 in the list above. 
# 
# As of XCode 11, XCode generates a directory '*.xcresult/' after tests are run. This 
# directory contains lots of data such as test coverage, test results, etc. We need to 
# use this directory of data to generate the test coverage file. It's also important 
# to generate a file format that CodeCov.io understands. 
#
# Use script: generate-code-coverage-report.sh
# 
# The final report that you should be uploading to CodeCov.io will be 1 file in directory: .build/generated/

set -e

OUTPUT_DIR=".build" # where swift package manager puts data. re-use that. 

# Install some tools that we need 
# mint allows us to execute a swift package manager executable
brew install mint jq

# We use Apple's xccov tool to take .xcresult/ and parse the code coverage report from that data. 
# We generate a json file with all the code coverage content in it. 
XCODE_CODE_COV_REPORT="$OUTPUT_DIR/code-coverage.json"
echo "Parsing .xcresult/ for code coverage to $XCODE_CODE_COV_REPORT"
xcrun xccov view --report *.xcresult --json > "$XCODE_CODE_COV_REPORT"

# We have now generated a human-readable file with code coverage information in it. However, CodeCov.io does not 
# understand the format that we generated with xccov. We need to convert that file into a different format. 

# Here, we are getting the list of SPM targets that we want code coverage for. We want all targets of the project minus targets having to do with tests. 
# jq takes JSON and prints it into a format that you want. the tool is quite powerful so let me try to explain what it is doing. 
# --join-output removes newline characters and prints the jq output all on one line. 
# select(.type == "regular") removes ".testTarget()" targets. 
# select(.name != "SharedTests") simply removes the "SharedTests" target as that's a ".target()" but still a target we don't care about test coverage for. 
# "--include-target \(.name) " is a template that we do string formatting for where jq inserts JSON values into it for us. 
TARGETS=$(swift package dump-package | jq --join-output '.targets[] | select(.type == "regular") | select(.name != "SharedTests") | "--include-target \(.name) "')
echo "Include targets command line argument: "
echo "\n\nExpected value of variable: a string with format: '--include-target foo --include-target bar'"
echo "Actual value: $TARGETS"
echo "\n\n"

# Run tool https://github.com/trax-retail/xccov2lcov to generate lcov file from 
# We need a lcov file because codecov.io does not understand the xccov file that Apple geneated. 
echo "Generating lcov report from json"
LCOV_REPORT="$OUTPUT_DIR/generated/code-coverage.info"
mkdir -p "$OUTPUT_DIR/generated"
# --trim-path takes '/full/path/to/customerio-ios/Sources/File.swift' and just turns it into '/Sources/File.swift' so that CodeCov.io understands what file we are talking about. 
mint run trax-retail/xccov2lcov@1.0.0 "$XCODE_CODE_COV_REPORT" --trim-path $(pwd) $TARGETS > "$LCOV_REPORT"
echo "Generated lcov report to $LCOV_REPORT"
