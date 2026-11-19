#!/bin/bash
# Record the whole monitor at 60 fps until Enter (by-hand clips) or until a
# command finishes (scripted clips). Crop and convert later with render.sh.
# Chips: a scripted take calls `chip "text"`, which logs the time to NAME.cues.
# Usage: demo/rec.sh NAME                  record, stop with Enter
#        demo/rec.sh NAME demo/takes.sh X  record while running take X
set -euo pipefail
source "$(dirname "$0")/env.sh"

name=$1; shift
monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
rm -f "$OUT_DIR/$name.cues"

gpu-screen-recorder -w "$monitor" -f 60 -fm cfr -k h264 -q very_high -cursor yes \
  -o "$OUT_DIR/$name.mp4" >/dev/null 2>&1 &
rec=$!
sleep 1.5   # the recorder needs a moment before its first frame
export CUES=$OUT_DIR/$name.cues START=$(date +%s.%N)

if (( $# )); then
  "$@"
  sleep 1
else
  read -rp "Recording $name; press Enter to stop. "
fi

kill -INT "$rec"; wait "$rec" || true
echo "$OUT_DIR/$name.mp4"
