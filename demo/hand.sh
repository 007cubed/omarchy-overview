#!/bin/bash
# A by-hand take, run detached on the demo machine so a dropped ssh cannot cut it:
# focus slot 2, record SECONDS, open the overview after a beat if asked, then
# go back to slot 10, where Orca shows the next instructions.
# Usage: setsid -f demo/hand.sh NAME SECONDS [overview]   (log: $STATE/hand.log)
set -euo pipefail
source "$(dirname "$0")/env.sh"

name=$1 seconds=$2 open=${3:-}
exec >"$STATE/hand.log" 2>&1

# Give the user time to leave Orca and look at the screen; the GIF is trimmed later.
# Orca, which shows the instructions, leaves slot 10 for the take: full-screen
# clips would show it in the overview.
orca() { hyprctl clients -j | jq -r '.[] | select(.class == "orca") | .address' |
  while read -r a; do dispatch "hl.dsp.window.move({ workspace = \"$1\", window = \"address:$a\", follow = false })"; done; }
(
  sleep 3.5
  orca special:demo-stash
  focus 2
  dispatch 'hl.dsp.focus({ window = "class:chromium-browser" })'
  [[ -n $open ]] && { sleep 1; overview; }
) &
"$DEMO_DIR/rec.sh" "$name" sleep "$seconds"
omarchy-shell -q shell hide guykawaii.overview
orca 10
focus 10
echo "done $name"
