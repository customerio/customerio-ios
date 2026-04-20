#!/usr/bin/env bash
# Bootstrap stub: clone (or update) the shared Maestro harness from
# https://github.com/customerio/mobile-e2e, then defer to its run.sh.
# All orchestration lives in the harness — this file only exports the
# per-sample APP_ID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

HARNESS_DIR="$SCRIPT_DIR/harness"
HARNESS_REPO="https://github.com/customerio/mobile-e2e.git"
if [[ ! -d "$HARNESS_DIR/.git" ]]; then
  echo ">> cloning harness from $HARNESS_REPO"
  git clone --depth 1 "$HARNESS_REPO" "$HARNESS_DIR"
else
  git -C "$HARNESS_DIR" pull --ff-only >/dev/null 2>&1 || true
fi

export PLATFORM="iOS"
export APP_ID="io.customer.ios-sample.apn-spm.APN-UIKit"
export HARNESS_DIR SAMPLE_MAESTRO_DIR="$SCRIPT_DIR"
exec bash "$HARNESS_DIR/run.sh" "$@"
