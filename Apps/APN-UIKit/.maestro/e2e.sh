#!/usr/bin/env bash
# Native-repo shortcut for the shared one-command mobile E2E runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HARNESS_DIR="${E2E_HARNESS_DIR:-$SCRIPT_DIR/harness}"
HARNESS_REPO="${E2E_HARNESS_REPO:-https://github.com/customerio/mobile-e2e.git}"
HARNESS_REF="${E2E_HARNESS_REF:-main}"
COMMAND="test"

if [[ "${1:-}" == "setup" ]]; then
  COMMAND="setup"
  shift
fi

if [[ -z "${E2E_HARNESS_DIR:-}" ]]; then
  if [[ ! -d "$HARNESS_DIR/.git" ]]; then
    echo ">> cloning shared E2E harness"
    git clone --depth 1 --branch "$HARNESS_REF" "$HARNESS_REPO" "$HARNESS_DIR"
  else
    git -C "$HARNESS_DIR" fetch --depth 1 origin "$HARNESS_REF" >/dev/null
    git -C "$HARNESS_DIR" checkout --detach FETCH_HEAD >/dev/null
  fi
fi

[[ -x "$HARNESS_DIR/e2e" ]] || {
  echo "error: shared E2E runner is missing at $HARNESS_DIR/e2e" >&2
  exit 2
}

exec "$HARNESS_DIR/e2e" "$COMMAND" \
  --platform ios \
  --ios-sdk-repo "$REPO_ROOT" \
  "$@"
