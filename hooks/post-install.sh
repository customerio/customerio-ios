#!/bin/bash

set -e

YELLOW='\033[0;33m'
RED='\033[0;31m'

echo -e "${RED}Hooks installed! Now, make sure that you have these tools installed on your machine:"

echo -e "${YELLOW}You need to install the program 'swiftformat' on your machine to continue."
echo -e "${YELLOW}The easiest way is 'brew install swiftformat'. If you're not on macOS, check out other instructions for installing: https://github.com/nicklockwood/SwiftFormat#command-line-tool"
echo ""
echo -e "${YELLOW}You need to install the program 'swiftlint' on your machine to continue."
echo -e "${YELLOW}The easiest way is 'brew install swiftlint'. If you're not on macOS, check out other instructions for installing: https://github.com/realm/SwiftLint#installation"
echo ""
echo -e "${YELLOW}If you would like to see what code you have not yet written reference docs for, uou need to install the program 'jazzy' on your machine to continue."
echo -e "${YELLOW}The easiest way is 'gem install jazzy'. Else, check out other instructions for installing: https://github.com/realm/jazzy/#installation"