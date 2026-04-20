#!/usr/bin/env bash
# Continuous simulator screenshot loop. Writes PNGs at ~5fps into the given dir
# until killed.
#
#   capture_frames.sh <sim_udid> <out_dir>

set -u
UDID="$1"
OUT_DIR="$(cd "$2" && pwd)"

i=0
while :; do
  f=$(printf "%s/f_%06d.png" "$OUT_DIR" "$i")
  xcrun simctl io "$UDID" screenshot "$f" >/dev/null 2>&1 || true
  i=$((i+1))
  sleep 0.2
done
