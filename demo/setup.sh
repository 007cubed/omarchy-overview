#!/bin/bash
# Build the demo stage: the same windows on the same slots before every take.
# Closes the windows the last run opened (and only those), then opens:
#   1 nvim · 2 chromium + foot · 3 three foots · 4 btop · 6 imv, floating · 7 two foots, scrolling
# Slots 5, 8, 9 and 10 stay empty as drop targets. Ends on slot 2.
# Usage: demo/setup.sh        demo/setup.sh clean   (only close the demo windows)
set -euo pipefail
source "$(dirname "$0")/env.sh"

PIDS=$STATE/pids

clean() {
  [[ -f $PIDS ]] || return 0
  while read -r pid; do kill "$pid" 2>/dev/null || true; done <"$PIDS"
  rm -f "$PIDS"
  sleep 1
}

count() { hyprctl clients -j | jq length; }

# Launch on the focused slot and wait until its window is mapped.
open() {
  local before
  before=$(count)
  setsid -f "$@" >/dev/null 2>&1
  for _ in $(seq 60); do
    (( $(count) > before )) && break
    sleep 0.25
  done
  hyprctl clients -j | jq -r 'min_by(.focusHistoryID) | .pid' >>"$PIDS"
  sleep 0.3
}

term() { local title=$1; shift; open foot -T "$title" -o locked-title=yes "$@"; }

layout() {
  for _ in 1 2 3; do
    [[ $(omarchy-hyprland-workspace-layout-current "$1") == "$2" ]] && return
    omarchy-hyprland-workspace-layout-toggle >/dev/null
    sleep 0.3
  done
}

clean
[[ ${1:-} == clean ]] && exit 0

focus 1; term nvim nvim "$REPO_DIR/Overview.qml"
focus 2
open chromium --user-data-dir="$STATE/chromium" --no-first-run --no-default-browser-check https://omarchy.org
term notes
focus 3; term one; term two; term three
focus 4; term btop btop
focus 6; layout 6 floating
open imv /usr/share/omarchy/themes/tokyo-night/backgrounds/6-oma-cityscape.jpg
focus 7; layout 7 scrolling; term left; term right
focus 2
dispatch 'hl.dsp.focus({ window = "class:chromium" })'
echo "Stage ready on slot 2: $(wc -l <"$PIDS") demo windows."
