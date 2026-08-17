#!/bin/sh

set -e # fail script if an error is encountered 

# Pushes a given Cocoapod to the Cocoapods server for deployment.
# Use script: ./scripts/push-cocoapod.sh CustomerIO.podspec
#
# Exit codes:
#   0  this version of the pod is on CocoaPods trunk
#   1  it is not, or we could not establish that it is
#   3  CocoaPods trunk is closed to writes, so nothing could be published

# We have cocoapods that depend on other cocoapods that we publish.
# Example: 
# Push - CustomerIODataPipelines version 1.1.1
# Push - CustomerIOMessagingPush version 1.1.1
# Pushing MessagingPush will fail because when you push a Cocoapod, the server you pushed to (the CDN)
# Takes a few minutes to refresh. Pushing the cocoapod will fail because it will say that 
# it cannot find the Tracking SDK version 1.1.1. 
# 
# To fix this issue, we use the --synchronous option when pushing. This uses the old (and slow) method of deploying 
# cocoapods using a git repo. 
# Learn more: https://github.com/CocoaPods/CocoaPods/issues/9497 

PODSPEC="$1"

if ! [[ -f "$PODSPEC" ]]; then
    echo "File $PODSPEC does not exist. Please check the pod name."
    exit 1
fi

# Read from the podspec, which is the file `pod trunk push` publishes, so what we
# ask trunk about cannot drift from what was pushed.
POD_NAME=$(grep -m1 -E '^[[:space:]]*spec\.name[[:space:]]*=' "$PODSPEC" | sed -nE 's/[^"]*"([^"]+)".*/\1/p')
VERSION=$(grep -m1 -E '^[[:space:]]*spec\.version[[:space:]]*=' "$PODSPEC" | sed -nE 's/[^"]*"([^"]+)".*/\1/p')
TRUNK_URL="https://trunk.cocoapods.org/api/v1/pods/$POD_NAME/versions/$VERSION"

# How long to let GitHub's post-commit hook reach trunk before asking whether a
# failed push actually landed. Spent only on the failure path.
TRUNK_SETTLE_SECONDS=45

# Both paths below need the name and version, and neither can say anything
# truthful without them. Defined once so an unreadable podspec cannot be a hard
# error on one path and a silent "trunk refused it" on the other.
require_pod_identity() {
  if [ -z "$POD_NAME" ] || [ -z "$VERSION" ]; then
    echo "::error::Could not read spec.name and spec.version from $PODSPEC, so trunk cannot be checked."
    exit 1
  fi
}

# Prints trunk's status for this exact version: 200 it holds it, 404 it does not,
# anything else the question could not be answered. curl's own error text is left
# on stderr, where the log needs it to tell an unreachable trunk from an absent
# pod. Trunk, not the CDN: the CDN lags publication by minutes, so it cannot tell
# "not published" apart from "not propagated yet".
trunk_status() {
  STATUS_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$TRUNK_URL") || STATUS_CODE="000"
  echo "$STATUS_CODE"
}

echo "Pushing podspec: $PODSPEC."
echo "If a pod version has already been published, it will be treated as success."
echo "For any other failure, the script will exit with a non-zero code."

OUTPUT=$(pod trunk push "$PODSPEC" --allow-warnings --synchronous 2>&1) || true
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "successfully published"; then
  echo "Pod $PODSPEC published successfully."
  exit 0
elif echo "$OUTPUT" | grep -q "Unable to accept duplicate entry for"; then
  echo "Pod $PODSPEC has already been published. Skipping."
  exit 0
elif echo "$OUTPUT" | grep -qi "we have closed pushing to cocoapods"; then
  # Trunk answers a push with this message and HTTP 503 while it is closed to
  # writes: a dry run 2026-11-01 to 11-07, then permanently from 2026-12-02.
  # https://blog.cocoapods.org/CocoaPods-Specs-Repo/
  # Nothing we change on our side can publish while it is closed, so this is
  # reported separately from a failure the next run could clear.
  #
  # Exit 3 rather than 2: the shell itself exits 2 on a syntax error, and the
  # caller would read that as "trunk is closed" and report a script that never
  # ran as a release nobody needs to look at.
  #
  # Trunk checks verify_pushes_allowed! before it checks for a duplicate entry,
  # so while it is closed even an already-published pod is answered with the 503.
  # Reads still work, so ask: without this, re-running a part-published release
  # during the read-only window would report every pod as refused and hide the
  # fact that some of them are on trunk.
  require_pod_identity
  TRUNK_CODE=$(trunk_status)

  if [ "$TRUNK_CODE" = "200" ]; then
    echo "Trunk is closed to writes, but it already holds $POD_NAME $VERSION."
    exit 0
  fi

  if [ "$TRUNK_CODE" != "404" ]; then
    # Only a 404 proves the pod is absent. Calling this a refusal without that
    # proof would let a part-published release be reported as a clean refusal,
    # which is green, and the partial would go unnoticed.
    echo "::error::CocoaPods trunk is closed to writes, and whether it already holds $POD_NAME $VERSION could not be checked (HTTP $TRUNK_CODE)."
    exit 1
  fi

  echo "::warning::CocoaPods trunk is closed to writes, so $PODSPEC was not published."
  exit 3
fi

# `pod trunk push` also reports a failure when the API call times out after
# trunk already accepted the podspec. That leaves a red release that is fixed by
# re-running it by hand until the duplicate-entry branch above catches it, which
# has cost several manual re-runs per release. Asking trunk which of the two
# happened removes the re-run.
require_pod_identity

# Asked once, after a wait, because trunk reports a version as published only
# once a Commit row exists (PodVersion#published? is `!deleted? && commits.any?`)
# and PodVersion#push! adds that row in the request only when GitHub answered it.
# When GitHub timed out or 5xx'd - the failure this whole check exists for - the
# row instead arrives from GitHub's post-commit hook, so an immediate question
# would answer 404 for a pod that is on its way in.
echo "Push reported a failure. Waiting ${TRUNK_SETTLE_SECONDS}s, then asking whether trunk holds $POD_NAME $VERSION."
sleep "$TRUNK_SETTLE_SECONDS"

HTTP_CODE=$(trunk_status)

if [ "$HTTP_CODE" = "200" ]; then
  # Deliberately not "the push succeeded": on a re-run this version may have been
  # on trunk before this run started. Warned rather than logged quietly so a push
  # that failed for a local reason - a lint error, an expired token - stays
  # visible in the run summary instead of vanishing into a green release.
  echo "::warning::$PODSPEC reported a push failure, but trunk holds $POD_NAME $VERSION. Treating it as published; see the push output above."
  exit 0
fi

if [ "$HTTP_CODE" = "404" ]; then
  # True but not the diagnosis: the push may have died before it reached trunk at
  # all, so point at the output that says why rather than at this check.
  echo "::error::Failed to push $PODSPEC, and trunk does not hold $POD_NAME $VERSION. The push output above is the cause."
  exit 1
fi

# Only 404 shows the pod is absent. Any other reply means the check did not work,
# which is worth saying rather than reporting the pod as definitely unpublished.
echo "::error::Failed to push $PODSPEC, and could not reach CocoaPods trunk to check whether it holds $POD_NAME $VERSION (HTTP $HTTP_CODE)."
exit 1
