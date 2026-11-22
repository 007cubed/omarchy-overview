#!/bin/bash
# Build the demo stage: the same windows on the same slots before every take.
# Closes the windows the last run opened (and only those), then opens:
#   1 nvim · 2 chromium + foot · 3 three foots · 4 btop · 6 imv, floating · 7 two foots, scrolling
# Slots 5, 8, 9 and 10 stay empty as drop targets. Ends on slot 2.
# The user's own windows wait on a hidden workspace meanwhile (Orca on slot 10).
# Usage: demo/setup.sh        demo/setup.sh clean   (close the demo windows, bring back the user's)
set -euo pipefail
source "$(dirname "$0")/env.sh"

PIDS=$STATE/pids STASH=$STATE/stash

move() { dispatch "hl.dsp.window.move({ workspace = \"$2\", window = \"address:$1\", follow = false })"; }

# The user's own windows wait on a hidden workspace while the stage is up;
# Orca, which guides the takes, stays reachable on slot 10, outside the crops.
stash() {
  [[ -f $STASH ]] && return 0
  hyprctl clients -j | jq -r '.[] | select(.workspace.id > 0) | "\(.address) \(.workspace.name) \(.class)"' |
    while read -r address workspace class; do
      echo "$address $workspace" >>"$STASH"
      if [[ $class == orca ]]; then move "$address" 10; else move "$address" special:demo-stash; fi
    done
}

unstash() {
  [[ -f $STASH ]] || return 0
  while read -r address workspace; do move "$address" "$workspace"; done <"$STASH"
  rm -f "$STASH"
}

clean() {
  if [[ -f $PIDS ]]; then
    # Each line is "pid start-time"; a pid reused after a reboot has another start time.
    while read -r pid start; do
      if [[ $(awk '{ print $22 }' "/proc/$pid/stat" 2>/dev/null) == "$start" ]]; then kill "$pid" || true; fi
    done <"$PIDS"
    rm -f "$PIDS"
    sleep 1
  fi
  rm -rf "$STATE/chromium"   # a killed profile asks to restore pages
}

addresses() { hyprctl clients -j | jq -r '.[].address' | sort; }

slot() { SLOT=$1; focus "$1"; }

# Launch on the current slot, wait until its window is mapped, keep its pid.
open() {
  local before new
  before=$(addresses)
  setsid -f "$@" >/dev/null 2>&1
  for _ in $(seq 60); do
    new=$(comm -13 <(echo "$before") <(addresses) | head -1)
    [[ -n $new ]] && break
    sleep 0.25
  done
  move "$new" "$SLOT"   # a slow window can map after focus moved on
  local pid
  pid=$(hyprctl clients -j | jq -r --arg a "$new" '.[] | select(.address == $a) | .pid')
  echo "$pid $(awk '{ print $22 }' "/proc/$pid/stat")" >>"$PIDS"
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
if [[ ${1:-} == clean ]]; then unstash; exit 0; fi
stash

# The page sits under /tmp so the address bar shows no home path. Chromium runs
# without extensions: system-wide ones open their own sign-in windows on a new
# profile, and the wrapper's flags load more.
page=/tmp/workspace-overview/index.html
mkdir -p "$(dirname "$page")" && cp "$DEMO_DIR/page.html" "$page"
slot 1; term nvim nvim "$REPO_DIR/Overview.qml"
slot 2
open /usr/lib/chromium/chromium --ozone-platform=wayland --user-data-dir="$STATE/chromium" \
  --no-first-run --no-default-browser-check --disable-extensions "file://$page"
term notes
slot 3; term one; term two; term three
slot 4; term btop btop
slot 6; layout 6 floating
open imv /usr/share/omarchy/themes/tokyo-night/backgrounds/6-oma-cityscape.jpg
slot 7; layout 7 scrolling; term left; term right
focus 2
dispatch 'hl.dsp.focus({ window = "class:chromium" })'
echo "Stage ready on slot 2: $(wc -l <"$PIDS") demo windows."
