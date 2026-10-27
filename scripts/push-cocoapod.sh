#!/bin/sh

set -e

# Push one podspec; the tier caller runs independent pods in parallel.
# Exit codes:
#   0  this exact pod version is on CocoaPods trunk, including earlier pushes
#   1  it is absent, or publication could not be confirmed
#   3  trunk is closed to writes and this version is confirmed absent
# Use 3 rather than 2 because the shell uses 2 for syntax errors, which must not
# be mistaken for a closed trunk by the caller.
PODSPEC="${1:-}"
if [ ! -f "$PODSPEC" ]; then
  echo "File $PODSPEC does not exist. Please check the pod name."
  exit 1
fi

POD_NAME=$(grep -m1 -E '^[[:space:]]*spec\.name[[:space:]]*=' "$PODSPEC" | sed -nE 's/[^"]*"([^"]+)".*/\1/p')
VERSION=$(grep -m1 -E '^[[:space:]]*spec\.version[[:space:]]*=' "$PODSPEC" | sed -nE 's/[^"]*"([^"]+)".*/\1/p')
if [ -z "$POD_NAME" ] || [ -z "$VERSION" ]; then
  echo "::error::Could not read spec.name and spec.version from $PODSPEC, so trunk cannot be checked."
  exit 1
fi
TRUNK_URL="https://trunk.cocoapods.org/api/v1/pods/$POD_NAME/versions/$VERSION"

# Three retries after the initial push, with 30/60/120 second backoff. Each
# transient failure gets a three-minute window for GitHub's hook to reach trunk.
# This bounds our waiting, not the pod command's own lint/build execution time.
MAX_PUSH_RETRIES=3
MAX_PUSH_ATTEMPTS=$((MAX_PUSH_RETRIES + 1))
TRUNK_SETTLE_SECONDS=180
TRUNK_POLL_INTERVAL_SECONDS=15
UNKNOWN_FAILURE_SETTLE_SECONDS=45

# Trunk's exact-version endpoint returns 200 only once a published Commit exists.
# The CDN lags publication and cannot answer whether this push landed.
trunk_status() {
  request_timeout=${1:-20}
  STATUS_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$request_timeout" "$TRUNK_URL") || STATUS_CODE="000"
  printf '%s\n' "$STATUS_CODE"
}

confirmed_after_failure() {
  # Keep the failed command visible even if another push or a late hook made
  # this version available. Confirmation does not prove this command succeeded.
  echo "::warning::$PODSPEC reported a push failure, but trunk holds $POD_NAME $VERSION. Treating it as published; see the push output above."
}

fail_publication() {
  if [ "$TRUNK_CODE" = "404" ]; then
    echo "::error::Failed to push $PODSPEC after $attempt push attempt(s), and trunk does not hold $POD_NAME $VERSION. The push output above is the cause."
  else
    echo "::error::Failed to push $PODSPEC after $attempt push attempt(s), and could not check whether trunk holds $POD_NAME $VERSION (HTTP $TRUNK_CODE)."
  fi
  exit 1
}

closed_trunk() {
  # Trunk rejects writes before checking duplicates. Reads still work, so a
  # version may already be published even when this push received a refusal.
  TRUNK_CODE=$(trunk_status)
  if [ "$TRUNK_CODE" = "200" ]; then
    echo "Trunk is closed to writes, but it already holds $POD_NAME $VERSION."
    exit 0
  fi
  if [ "$TRUNK_CODE" != "404" ]; then
    # Only 404 proves absence; an unavailable check is a failure, not a refusal.
    echo "::error::CocoaPods trunk is closed to writes, and whether it already holds $POD_NAME $VERSION could not be checked (HTTP $TRUNK_CODE)."
    exit 1
  fi
  echo "::warning::CocoaPods trunk is closed to writes, so $PODSPEC was not published."
  exit 3
}

transient_failure() {
  # The CLI prints the JSON error body without its HTTP status. These are the
  # actual trunk timeout/server-error messages, plus explicit HTTP/gateway and
  # transport errors. Bare numbers or class names in build logs must not match.
  printf '%s\n' "$OUTPUT" | grep -Eiq \
    'Calling the GitHub commit API timed out|An error occurred on GitHub|An internal server error occurred|Bad Gateway|Gateway Time-?out|Service Unavailable|(HTTP|status( code)?)[[:space:]:=-]+5[0-9]{2}([^0-9]|$)|HTTP/[0-9.]+[[:space:]]+5[0-9]{2}([^0-9]|$)|Net::(Read|Open)Timeout|execution expired|connection (timed out|reset)|Failed to open TCP connection'
}

wait_for_publication() {
  settle_deadline=$(( $(date +%s) + TRUNK_SETTLE_SECONDS ))
  while :; do
    remaining=$((settle_deadline - $(date +%s)))
    if [ "$remaining" -le 0 ]; then
      return 1
    fi
    timeout=$remaining
    if [ "$timeout" -gt 20 ]; then
      timeout=20
    fi
    TRUNK_CODE=$(trunk_status "$timeout")
    if [ "$TRUNK_CODE" = "200" ]; then
      confirmed_after_failure
      return 0
    fi
    remaining=$((settle_deadline - $(date +%s)))
    if [ "$remaining" -le 0 ]; then
      return 1
    fi
    pause=$TRUNK_POLL_INTERVAL_SECONDS
    if [ "$pause" -gt "$remaining" ]; then
      pause=$remaining
    fi
    sleep "$pause"
  done
}

# Skip before CocoaPods performs expensive validation, including on a rerun
# during trunk's read-only window. Unknown read status does not block a push.
TRUNK_CODE=$(trunk_status)
if [ "$TRUNK_CODE" = "200" ]; then
  echo "Trunk already holds $POD_NAME $VERSION. Skipping $PODSPEC."
  exit 0
fi

attempt=1
backoff=30
while :; do
  echo "Pushing podspec: $PODSPEC (attempt $attempt of $MAX_PUSH_ATTEMPTS)."
  # --synchronous uses the git Specs repo so later tiers need not wait for the
  # CDN to serve their exact-version dependencies.
  # https://github.com/CocoaPods/CocoaPods/issues/9497
  OUTPUT=$(pod trunk push "$PODSPEC" --allow-warnings --synchronous 2>&1) || true
  printf '%s\n' "$OUTPUT"

  if printf '%s\n' "$OUTPUT" | grep -q 'successfully published'; then
    echo "Pod $PODSPEC published successfully."
    exit 0
  elif printf '%s\n' "$OUTPUT" | grep -q 'Unable to accept duplicate entry for'; then
    echo "Pod $PODSPEC has already been published. Skipping."
    exit 0
  elif printf '%s\n' "$OUTPUT" | grep -qi 'we have closed pushing to cocoapods'; then
    # Closed trunk is its own 503, not a transient server failure to retry.
    closed_trunk
  elif transient_failure; then
    echo "Transient push failure. Checking trunk for up to ${TRUNK_SETTLE_SECONDS}s before another push."
    if wait_for_publication; then
      exit 0
    fi
    if [ "$attempt" -ge "$MAX_PUSH_ATTEMPTS" ]; then
      fail_publication
    fi
    echo "Trunk has not confirmed $POD_NAME $VERSION. Retrying after ${backoff}s."
    sleep "$backoff"
    # The hook may have arrived during backoff; do not re-lint a published pod.
    TRUNK_CODE=$(trunk_status)
    if [ "$TRUNK_CODE" = "200" ]; then
      confirmed_after_failure
      exit 0
    fi
    attempt=$((attempt + 1))
    backoff=$((backoff * 2))
  else
    # Preserve the confirming read for unclassified failures: a concurrent push
    # may have landed even though this command failed lint/auth/another check.
    echo "Push reported a failure. Waiting ${UNKNOWN_FAILURE_SETTLE_SECONDS}s, then checking trunk."
    sleep "$UNKNOWN_FAILURE_SETTLE_SECONDS"
    TRUNK_CODE=$(trunk_status)
    if [ "$TRUNK_CODE" = "200" ]; then
      confirmed_after_failure
      exit 0
    fi
    fail_publication
  fi
done
