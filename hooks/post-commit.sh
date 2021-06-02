#!/bin/bash

set -e

RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
GREEN='\033[0;32m'

# using "| xargs" to remove whitespace from wc command 
UNTRACKED_FILES_COUNT="$(git ls-files --exclude-standard --others | wc -l | xargs)"
NOT_STAGED_FILES_COUNT="$(git diff --name-only | wc -l | xargs)"

if [ "$UNTRACKED_FILES_COUNT" != "0" ] || [ "$NOT_STAGED_FILES_COUNT" != "0" ]; then 
    echo -e "\n${YELLOW}*** NOTE: ***${WHITE}"
    echo -e "${YELLOW}swiftformat modified some files from your past commit. I recommend a quick..."
    echo -e "${GREEN}\"git add <files> && git commit --amend\""
    echo -e "${YELLOW}...for those modified files to include those changes in the past commit${WHITE}\n"
fi 