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
FORMATTER_SCRIPT="./scripts/format-api-docs.rb"

# Module configuration: scheme_name:module_name
# Based on Package.swift and available schemes
# Public modules (always available)
declare -a PUBLIC_MODULES=(
    "DataPipelines:CioDataPipelines"
    "MessagingPushAPN:CioMessagingPushAPN" 
    "MessagingPushFCM:CioMessagingPushFCM"
    "MessagingInApp:CioMessagingInApp"
)

# Internal modules (only available when CI environment variable is set)
# These are conditionally added to Package.swift products array in CI
declare -a INTERNAL_MODULES=()

# Check if we're in CI environment, these modules are only added on CI as products, check Package.swift
if [ -n "$CI" ]; then
    echo -e "${GREEN}✅ Internal modules detected - adding to generation list${NC}"
    INTERNAL_MODULES+=(
        "InternalCommon:CioInternalCommon"
        "Migration:CioTrackingMigration"
        "Customer.io-Package:CioMessagingPush"
    )
else
    echo -e "${YELLOW}⚠️  Internal modules not available (not in CI environment)${NC}"
fi

# Combine all modules
declare -a MODULES=("${PUBLIC_MODULES[@]}" "${INTERNAL_MODULES[@]}")

# Track module failures
FAILED_MODULES=()
OVERALL_SUCCESS=true

echo -e "${BLUE}🚀 Starting API documentation generation...${NC}"

# Validate Package.swift exists (required for Swift Package Manager builds)
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Package.swift not found in current directory${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this from the project root${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Package.swift found - using Swift Package Manager build${NC}"


find_ios_simulator() {
    # Just grab the first available iPhone simulator
    local simulator_line=$(xcrun simctl list devices available | grep "iPhone" | head -1)
    
    if [ -n "$simulator_line" ]; then
        # Extract the device ID from the line
        local device_id=$(echo "$simulator_line" | sed 's/.*(\([A-F0-9-]*\)).*/\1/')
        echo "platform=iOS Simulator,id=$device_id"
        return 0
    else
        # Fallback to a generic destination if no simulators found
        echo "platform=iOS Simulator,name=iPhone SE (3rd generation)"
        return 1
    fi
}

DESTINATION=$(find_ios_simulator)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Using destination: $DESTINATION${NC}"
else
    echo -e "${YELLOW}⚠️  Using fallback destination: $DESTINATION${NC}"
fi

# Create docs directory
mkdir -p "$DOCS_DIR"
mkdir -p "$DOCS_DIR/internal"

# Generate documentation for each module
for module_config in "${MODULES[@]}"; do
    # Split scheme:module
    IFS=':' read -r scheme_name module_name <<< "$module_config"
    
    echo -e "\n${BLUE}📖 Generating documentation for $module_name (scheme: $scheme_name)...${NC}"
    
    # Check if this is an internal module by looking for it in INTERNAL_MODULES
    if [[ "${INTERNAL_MODULES[*]}" =~ ":${module_name}" ]]; then
        # Internal module - save to internal subdirectory
        RAW_JSON_FILE="$DOCS_DIR/internal/${module_name}.json"
        FORMATTED_FILE="$DOCS_DIR/internal/${module_name}.api"

    else
        # Public module - save to main directory
        RAW_JSON_FILE="$DOCS_DIR/${module_name}.json"
        FORMATTED_FILE="$DOCS_DIR/${module_name}.api"
    fi
    
    # Generate raw JSON documentation using sourcekitten
    echo -e "${YELLOW}   🔍 Extracting API with sourcekitten...${NC}"
    
    # Try generating the documentation and capture any errors
    if sourcekitten doc \
        --module-name "$module_name" \
        -- \
        -scheme "$scheme_name" \
        -destination "$DESTINATION" > "$RAW_JSON_FILE" 2>/tmp/sourcekitten_error_${module_name}.log; then
        
        # Format the documentation using Ruby script
        if ruby "$FORMATTER_SCRIPT" "$RAW_JSON_FILE" > "$FORMATTED_FILE"; then
            echo -e "${GREEN}   ✅ Generated: $FORMATTED_FILE${NC}"
            # Remove the intermediate JSON file after successful formatting
            rm "$RAW_JSON_FILE"
        else
            echo -e "${RED}   ❌ Failed to format documentation for $module_name${NC}"
            # Keep the raw JSON even if formatting fails
            FAILED_MODULES+=("$module_name (formatting failed)")
            OVERALL_SUCCESS=false
            continue
        fi
        
    else
        echo -e "${RED}   ❌ Failed to generate raw documentation for $module_name${NC}"
        
        # Show the actual error from sourcekitten/xcodebuild
        if [ -f "/tmp/sourcekitten_error_${module_name}.log" ]; then
            echo -e "${RED}   🔍 Error details:${NC}"
            tail -10 /tmp/sourcekitten_error_${module_name}.log | sed 's/^/      /'
        fi
        
        echo -e "${YELLOW}   💡 Try running manually to debug:${NC}"
        echo -e "${YELLOW}      sourcekitten doc --module-name \"$module_name\" -- -scheme \"$scheme_name\" -destination \"$DESTINATION\" 2>/tmp/sourcekitten_error_${module_name}.log${NC}"
        
        # Track this failure
        FAILED_MODULES+=("$module_name (sourcekitten failed)")
        OVERALL_SUCCESS=false
        continue
    fi
done

echo -e "\n${BLUE}📊 API Documentation Generation Summary${NC}"
printf '=%.0s' {1..50}
echo

if [ "$OVERALL_SUCCESS" = true ]; then
    echo -e "${GREEN}🎉 All modules successfully generated!${NC}"
    echo -e "${GREEN}✅ API documentation generation complete!${NC}"
else
    echo -e "${RED}⚠️  Some modules failed to generate documentation${NC}"
    echo -e "\n${RED}Failed modules (${#FAILED_MODULES[@]}):${NC}"
    for failed_module in "${FAILED_MODULES[@]}"; do
        echo -e "  ${RED}❌ $failed_module${NC}"
    done
    
    echo -e "\n${RED}❌ API documentation generation failed for some modules${NC}"
    exit 1
fi
