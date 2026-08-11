#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  XCODE27_EXPECTED_IMAGE_VERSION
  XCODE27_EXPECTED_MACOS_VERSION
  XCODE27_EXPECTED_MACOS_BUILD
  XCODE27_EXPECTED_ARCHITECTURE
  XCODE27_EXPECTED_VERSION
  XCODE27_EXPECTED_BUILD
  XCODE27_EXPECTED_APP_PATH
  XCODE27_EXPECTED_IPHONEOS_SDK
  XCODE27_EXPECTED_SIMULATOR_SDK
  XCODE27_EXPECTED_IOS_RUNTIME
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required pin variable: $variable_name" >&2
    exit 2
  fi
done

write_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

write_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

record_drift() {
  drift_reasons+=("$1")
}

actual_image_version="${ImageVersion:-missing}"
actual_macos_version="$(sw_vers -productVersion)"
actual_macos_build="$(sw_vers -buildVersion)"
actual_architecture="$(uname -m)"

echo "Xcode 27 preview runner evidence"
echo "  ImageOS: ${ImageOS:-missing}"
echo "  ImageVersion: $actual_image_version"
echo "  macOS: $actual_macos_version ($actual_macos_build)"
echo "  architecture: $actual_architecture"
echo "  expected Xcode app: $XCODE27_EXPECTED_APP_PATH"

drift_reasons=()

[[ "$actual_image_version" == "$XCODE27_EXPECTED_IMAGE_VERSION" ]] || \
  record_drift "ImageVersion expected $XCODE27_EXPECTED_IMAGE_VERSION, found $actual_image_version"
[[ "$actual_macos_version" == "$XCODE27_EXPECTED_MACOS_VERSION" ]] || \
  record_drift "macOS version expected $XCODE27_EXPECTED_MACOS_VERSION, found $actual_macos_version"
[[ "$actual_macos_build" == "$XCODE27_EXPECTED_MACOS_BUILD" ]] || \
  record_drift "macOS build expected $XCODE27_EXPECTED_MACOS_BUILD, found $actual_macos_build"
[[ "$actual_architecture" == "$XCODE27_EXPECTED_ARCHITECTURE" ]] || \
  record_drift "architecture expected $XCODE27_EXPECTED_ARCHITECTURE, found $actual_architecture"

actual_xcode_version="missing"
actual_xcode_build="missing"
actual_iphoneos_sdk="missing"
actual_simulator_sdk="missing"
runtime_available=false

if [[ -d "$XCODE27_EXPECTED_APP_PATH" ]]; then
  export DEVELOPER_DIR="$XCODE27_EXPECTED_APP_PATH/Contents/Developer"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
  fi

  if xcode_version_output="$(xcodebuild -version 2>&1)"; then
    actual_xcode_version="$(awk '/^Xcode / { print $2; exit }' <<< "$xcode_version_output")"
    actual_xcode_build="$(awk '/^Build version / { print $3; exit }' <<< "$xcode_version_output")"
  else
    record_drift "xcodebuild could not inspect $XCODE27_EXPECTED_APP_PATH: $xcode_version_output"
  fi
  if ! actual_iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-version 2>&1)"; then
    record_drift "xcrun could not inspect the iphoneos SDK: $actual_iphoneos_sdk"
  fi
  if ! actual_simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-version 2>&1)"; then
    record_drift "xcrun could not inspect the iphonesimulator SDK: $actual_simulator_sdk"
  fi

  echo
  echo "$xcode_version_output"
  echo "iphoneos SDK: $actual_iphoneos_sdk"
  echo "iphonesimulator SDK: $actual_simulator_sdk"
  echo
  if ! xcodebuild -showsdks; then
    record_drift "xcodebuild could not list installed SDKs"
  fi
  echo
  if ! xcrun simctl list runtimes; then
    record_drift "simctl could not list installed runtimes"
  fi

  runtime_json=""
  if ! runtime_json="$(xcrun simctl list runtimes --json 2>&1)"; then
    record_drift "simctl could not read runtime metadata: $runtime_json"
  elif /usr/bin/python3 -c '
import json
import sys

expected = sys.argv[1]
runtimes = json.load(sys.stdin).get("runtimes", [])
available = any(
    runtime.get("identifier") == expected and runtime.get("isAvailable", False)
    for runtime in runtimes
)
raise SystemExit(0 if available else 1)
' "$XCODE27_EXPECTED_IOS_RUNTIME" <<< "$runtime_json"; then
    runtime_available=true
  fi

  [[ "$actual_xcode_version" == "$XCODE27_EXPECTED_VERSION" ]] || \
    record_drift "Xcode version expected $XCODE27_EXPECTED_VERSION, found $actual_xcode_version"
  [[ "$actual_xcode_build" == "$XCODE27_EXPECTED_BUILD" ]] || \
    record_drift "Xcode build expected $XCODE27_EXPECTED_BUILD, found $actual_xcode_build"
  [[ "$actual_iphoneos_sdk" == "$XCODE27_EXPECTED_IPHONEOS_SDK" ]] || \
    record_drift "iphoneos SDK expected $XCODE27_EXPECTED_IPHONEOS_SDK, found $actual_iphoneos_sdk"
  [[ "$actual_simulator_sdk" == "$XCODE27_EXPECTED_SIMULATOR_SDK" ]] || \
    record_drift "iphonesimulator SDK expected $XCODE27_EXPECTED_SIMULATOR_SDK, found $actual_simulator_sdk"
  [[ "$runtime_available" == true ]] || \
    record_drift "available runtime $XCODE27_EXPECTED_IOS_RUNTIME was not found"
else
  record_drift "Xcode app is missing at $XCODE27_EXPECTED_APP_PATH"
fi

write_output image-version "$actual_image_version"
write_output xcode-build "$actual_xcode_build"
write_output xcode-version "$actual_xcode_version"
write_output simulator-sdk "$actual_simulator_sdk"

write_summary "## Xcode 27 preview toolchain"
write_summary ""
write_summary "| Field | Expected | Actual |"
write_summary "| --- | --- | --- |"
write_summary "| ImageVersion | \`$XCODE27_EXPECTED_IMAGE_VERSION\` | \`$actual_image_version\` |"
write_summary "| macOS | \`$XCODE27_EXPECTED_MACOS_VERSION ($XCODE27_EXPECTED_MACOS_BUILD)\` | \`$actual_macos_version ($actual_macos_build)\` |"
write_summary "| Architecture | \`$XCODE27_EXPECTED_ARCHITECTURE\` | \`$actual_architecture\` |"
write_summary "| Xcode | \`$XCODE27_EXPECTED_VERSION ($XCODE27_EXPECTED_BUILD)\` | \`$actual_xcode_version ($actual_xcode_build)\` |"
write_summary "| iphoneos SDK | \`$XCODE27_EXPECTED_IPHONEOS_SDK\` | \`$actual_iphoneos_sdk\` |"
write_summary "| iphonesimulator SDK | \`$XCODE27_EXPECTED_SIMULATOR_SDK\` | \`$actual_simulator_sdk\` |"
write_summary "| iOS runtime available | \`$XCODE27_EXPECTED_IOS_RUNTIME\` | \`$runtime_available\` |"

if (( ${#drift_reasons[@]} > 0 )); then
  write_output classification preview-infrastructure-drift
  write_summary ""
  write_summary "**Classification:** preview-infrastructure-drift"
  for reason in "${drift_reasons[@]}"; do
    echo "::error title=Xcode 27 preview infrastructure drift::$reason"
    write_summary "- $reason"
  done
  exit 1
fi

write_output classification verified-toolchain
write_summary ""
write_summary "**Classification:** verified-toolchain"
echo "Pinned Xcode 27 preview toolchain verified."
