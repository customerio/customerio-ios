#!/bin/bash

set -e

RED='\033[0;31m'
YELLOW='\033[0;33m'

if ! [ -x "$(command -v swiftformat)" ]; then
    echo -e "${RED}You need to install the program 'swiftformat' on your machine to continue."
    echo ""
    echo -e "${RED}The easiest way is 'brew install swiftformat'. If you're not on macOS, check out other instructions for installing: https://github.com/nicklockwood/SwiftFormat#command-line-tool"
else
    make format
fi