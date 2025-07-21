#!/bin/bash

set -e

# Script to generate API documentation for all Customer.io iOS SDK modules
# This script uses sourcekitten to extract raw API documentation and formats it 
# using the Ruby formatter script for clean, readable output.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOCS_DIR="api-docs"
DESTINATION="platform=iOS Simulator,name=iPhone 16"
FORMATTER_SCRIPT="./scripts/format-api-docs.rb"

# Module configuration: scheme_name:module_name
# Based on Package.swift and available schemes
declare -a MODULES=(
    "DataPipelines:CioDataPipelines"
    "MessagingPushAPN:CioMessagingPushAPN" 
    "MessagingPushFCM:CioMessagingPushFCM"
    "MessagingInApp:CioMessagingInApp"
)

echo -e "${BLUE}🚀 Starting API documentation generation...${NC}"

# Create docs directory
echo -e "${YELLOW}📁 Creating documentation directory...${NC}"
mkdir -p "$DOCS_DIR"

# Check available simulators
echo -e "${YELLOW}📱 Checking available simulators...${NC}"
BOOTED_SIMULATOR=$(xcrun simctl list devices | grep "Booted" | head -1 | sed 's/.*(\([^)]*\)).*/\1/' || echo "")
if [ -n "$BOOTED_SIMULATOR" ]; then
    DESTINATION="platform=iOS Simulator,id=$BOOTED_SIMULATOR"
    echo -e "${GREEN}✅ Using booted simulator: $BOOTED_SIMULATOR${NC}"
else
    echo -e "${YELLOW}⚠️  No booted simulator found, using default: iPhone 16${NC}"
fi

# Generate documentation for each module
for module_config in "${MODULES[@]}"; do
    # Split scheme:module
    IFS=':' read -r scheme_name module_name <<< "$module_config"
    
    echo -e "\n${BLUE}📖 Generating documentation for $module_name (scheme: $scheme_name)...${NC}"
    
    # File paths
    RAW_JSON_FILE="$DOCS_DIR/${module_name}.json"
    FORMATTED_FILE="$DOCS_DIR/${module_name}.api"
    
    # Generate raw JSON documentation using sourcekitten
    echo -e "${YELLOW}   🔍 Extracting API with sourcekitten...${NC}"
    if sourcekitten doc \
        --module-name "$module_name" \
        -- \
        -scheme "$scheme_name" \
        -destination "$DESTINATION" > "$RAW_JSON_FILE"; then
        
        echo -e "${GREEN}   ✅ Raw JSON generated: $RAW_JSON_FILE${NC}"
        
        # Format the documentation using Ruby script
        echo -e "${YELLOW}   🎨 Formatting documentation...${NC}"
        if ruby "$FORMATTER_SCRIPT" "$RAW_JSON_FILE" > "$FORMATTED_FILE"; then
            echo -e "${GREEN}   ✅ Formatted documentation: $FORMATTED_FILE${NC}"
            # Remove the intermediate JSON file after successful formatting
            rm "$RAW_JSON_FILE"
            echo -e "${GREEN}   🗑️  Removed intermediate JSON file${NC}"
        else
            echo -e "${RED}   ❌ Failed to format documentation for $module_name${NC}"
            # Keep the raw JSON even if formatting fails
            continue
        fi
        
    else
        echo -e "${RED}   ❌ Failed to generate raw documentation for $module_name${NC}"
        continue
    fi
done
