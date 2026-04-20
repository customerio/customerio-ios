#!/usr/bin/env bash
# Run a Maestro flow end-to-end on an iOS simulator and produce the full
# artifact bundle: HTML tick-mark report, annotated side-by-side MP4, and
# a sink.jsonl of backend values captured during the run.
#
#   .maestro/run.sh [flow-file]    # defaults to maestro_test_campaign.yaml
#
# Requires: Xcode CLT (xcrun simctl), maestro on PATH, python3 + Pillow,
# ffmpeg, and .maestro/.env with MAESTRO_EXT_API_KEY=<bearer token>.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# --- Shared harness: sink + report/video renderers + Ext-API assertion helper.
# Pulled from https://github.com/customerio/mobile-e2e on first run and
# refreshed on subsequent runs. Gitignored in this repo.
HARNESS_DIR="$SCRIPT_DIR/harness"
HARNESS_REPO="https://github.com/customerio/mobile-e2e.git"
if [[ ! -d "$HARNESS_DIR/.git" ]]; then
  echo ">> cloning harness from $HARNESS_REPO"
  git clone --depth 1 "$HARNESS_REPO" "$HARNESS_DIR"
else
  git -C "$HARNESS_DIR" pull --ff-only >/dev/null 2>&1 || true
fi

FLOW="${1:-campaign_141.yaml}"
FLOW_NAME="$(basename "$FLOW" .yaml)"
OUT_DIR="artifacts/$FLOW_NAME"
DEBUG_DIR="$OUT_DIR/debug"

# Flow resolution: prefer a local override in .maestro/, fall back to the
# shared flow in the harness.
resolve_flow() {
  local name="$1"
  if [[ -f ".maestro/$name" ]]; then echo ".maestro/$name"; return; fi
  if [[ -f ".maestro/harness/flows/$name" ]]; then echo ".maestro/harness/flows/$name"; return; fi
  echo "" ; return
}

mkdir -p "$OUT_DIR" "$DEBUG_DIR"
rm -rf "$DEBUG_DIR"/*

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi
if [[ -z "${MAESTRO_EXT_API_KEY:-}" ]]; then
  echo "warn: MAESTRO_EXT_API_KEY not set; backend assertions will fail auth" >&2
fi

BOOTED=$(xcrun simctl list devices booted 2>&1 | grep -Eo '\(([0-9A-F-]{36})\) \(Booted\)' | head -1 | grep -Eo '[0-9A-F-]{36}' || true)
if [[ -z "$BOOTED" ]]; then
  echo "error: no booted iOS simulator. Boot one in Simulator.app and retry." >&2
  exit 2
fi
echo ">> simulator: $BOOTED"

echo ">> starting local sink (captures backend assertion values)"
SINK_LOG="$OUT_DIR/sink.jsonl"
python3 "$HARNESS_DIR/scripts/sink.py" "$SINK_LOG" --port 8899 >"$OUT_DIR/sink.stderr" 2>&1 &
SINK_PID=$!
for _ in 1 2 3 4 5; do
  if curl -s -o /dev/null http://127.0.0.1:8899/ ; then break; fi
  sleep 0.2
done

echo ">> starting simulator screenshot capture loop"
# simctl recordVideo collides with maestro's live simulator session, so we
# poll screenshots at ~5fps instead and assemble them into an mp4 afterward.
FRAMES_DIR="$OUT_DIR/frames"
rm -rf "$FRAMES_DIR" && mkdir -p "$FRAMES_DIR"
chmod +x "$HARNESS_DIR/scripts/capture_frames.sh"
"$HARNESS_DIR/scripts/capture_frames.sh" "$BOOTED" "$FRAMES_DIR" \
    >"$OUT_DIR/capture.log" 2>&1 &
REC_PID=$!
REC_STARTED_AT_MS=$(python3 -c "import time;print(int(time.time()*1000))")

cleanup() {
  kill "$REC_PID" >/dev/null 2>&1 || true
  wait "$REC_PID" 2>/dev/null || true
  kill "$SINK_PID" >/dev/null 2>&1 || true
  wait "$SINK_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo ">> running maestro: $FLOW"
set +e
FLOW_PATH="$(resolve_flow "$FLOW")"
if [[ -z "$FLOW_PATH" ]]; then
  echo "error: flow '$FLOW' not found in .maestro/ or .maestro/harness/flows/" >&2
  exit 2
fi
echo ">> running maestro: $FLOW_PATH"
maestro --device "$BOOTED" test \
  --format=HTML \
  --output="$OUT_DIR/report.html" \
  --debug-output="$DEBUG_DIR" \
  --flatten-debug-output \
  -e APP_ID=io.customer.ios-sample.apn-spm.APN-UIKit \
  "$FLOW_PATH" \
  | tee "$OUT_DIR/run.log"
EXIT=$?
set -e

echo ">> stopping screenshot capture"
kill "$REC_PID" >/dev/null 2>&1 || true
wait "$REC_PID" 2>/dev/null || true

echo ">> stopping sink"
kill "$SINK_PID" >/dev/null 2>&1 || true
wait "$SINK_PID" 2>/dev/null || true

echo ">> assembling frames into mp4 (5fps)"
DEVICE_MP4="$OUT_DIR/device.mp4"
FRAME_COUNT=$(ls "$FRAMES_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$FRAME_COUNT" -gt 0 ]]; then
  # Scale to a reasonable height; keep aspect. 5fps captures the motion well enough.
  ffmpeg -y -framerate 5 -i "$FRAMES_DIR/f_%06d.png" \
    -vf "scale=-2:1280:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 22 \
    "$DEVICE_MP4" >/dev/null 2>&1 \
    || echo "warn: frame assembly failed"
fi
# Free disk: remove raw frames once mp4 exists.
if [[ -f "$DEVICE_MP4" ]]; then rm -rf "$FRAMES_DIR"; fi

echo ">> rendering tick-mark report"
python3 "$HARNESS_DIR/scripts/render_report.py" \
  "$DEBUG_DIR" \
  "$OUT_DIR/tickmarks.html" \
  --screens-dir artifacts \
  --video "$DEVICE_MP4" \
  --sink "$SINK_LOG" \
  --title "iOS $FLOW_NAME"

echo ">> rendering annotated side-by-side video"
if [[ -f "$DEVICE_MP4" ]]; then
  python3 "$HARNESS_DIR/scripts/render_video.py" \
    --commands "$DEBUG_DIR"/commands-*.json \
    --device "$DEVICE_MP4" \
    --rec-started-ms "$REC_STARTED_AT_MS" \
    --sink "$SINK_LOG" \
    --out "$OUT_DIR/annotated.mp4" \
    || echo "warn: annotated video render failed"
fi

echo ">> done: $OUT_DIR/tickmarks.html (exit=$EXIT)"
open "$OUT_DIR/tickmarks.html" 2>/dev/null || true
open "$OUT_DIR/annotated.mp4" 2>/dev/null || true
exit "$EXIT"
