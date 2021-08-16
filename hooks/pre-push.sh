#!/bin/bash

set -e

RED='\033[0;31m'
YELLOW='\033[0;33m'

if ! [ -x "$(command -v swiftlint)" ]; then
    echo -e "${RED}You need to install the program 'swiftlint' on your machine to continue."
    echo ""
    echo -e "${RED}The easiest way is 'brew install swiftlint'. If you're not on macOS, check out other instructions for installing: https://github.com/realm/SwiftLint#installation"
else
    make lint || true 
fi

if ! [ -x "$(command -v jazzy)" ]; then
    echo -e "${YELLOW}If you would like to see what code you have not yet written reference docs for, uou need to install the program 'jazzy' on your machine to continue."
    echo ""
    echo -e "${YELLOW}The easiest way is 'gem install jazzy'. Else, check out other instructions for installing: https://github.com/realm/jazzy/#installation"
else
    make check-undocumented || true
fi