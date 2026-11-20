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
  rm -rf "$STATE/chromium"   # a killed profile asks to restore pages
}

addresses() { hyprctl clients -j | jq -r '.[].address' | sort; }

# Launch on the focused slot, wait until its window is mapped, keep its pid.
open() {
  local before new
  before=$(addresses)
  setsid -f "$@" >/dev/null 2>&1
  for _ in $(seq 60); do
    new=$(comm -13 <(echo "$before") <(addresses) | head -1)
    [[ -n $new ]] && break
    sleep 0.25
  done
  hyprctl clients -j | jq -r --arg a "$new" '.[] | select(.address == $a) | .pid' >>"$PIDS"
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

# The page sits under /tmp so the address bar shows no home path. Chromium runs
# without extensions: system-wide ones open their own sign-in windows on a new
# profile, and the wrapper's flags load more.
page=/tmp/workspace-overview/index.html
mkdir -p "$(dirname "$page")" && cp "$DEMO_DIR/page.html" "$page"
focus 1; term nvim nvim "$REPO_DIR/Overview.qml"
focus 2
open /usr/lib/chromium/chromium --ozone-platform=wayland --user-data-dir="$STATE/chromium" \
  --no-first-run --no-default-browser-check --disable-extensions "file://$page"
term notes
focus 3; term one; term two; term three
focus 4; term btop btop
focus 6; layout 6 floating
open imv /usr/share/omarchy/themes/tokyo-night/backgrounds/6-oma-cityscape.jpg
focus 7; layout 7 scrolling; term left; term right
focus 2
dispatch 'hl.dsp.focus({ window = "class:chromium" })'
echo "Stage ready on slot 2: $(wc -l <"$PIDS") demo windows."
