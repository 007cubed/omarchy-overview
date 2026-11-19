#!/bin/bash
# The scripted takes. Run through rec.sh: demo/rec.sh switch-hint demo/takes.sh switch-hint
# Start each from a fresh demo/setup.sh.
set -euo pipefail
source "$(dirname "$0")/env.sh"

# Log a chip (key label) at the current time for render.sh.
chip() { printf '%s\t%s\n' "$(awk -v a="$(date +%s.%N)" -v b="$START" 'BEGIN { printf "%.2f", a - b }')" "$1" >>"$CUES"; }
key() { chip "$1"; shift; wtype "$@"; sleep 0.8; }

case $1 in
  switch-hint)
    sleep 0.8
    chip "Super + 3";         focus 3; sleep 0.9
    chip "Super + 8";         focus 8; sleep 0.9
    chip "Super + 2";         focus 2; sleep 0.9
    chip "Super + Shift + 3"; carry 3; sleep 1.2
    ;;
  keyboard)
    overview; sleep 1
    key "→" -k Right
    key "Shift + 8" -M shift -k 8 -m shift
    key "↓" -k Down
    key "Enter" -k Return
    sleep 0.6
    overview; sleep 1
    key "4" -k 4
    sleep 0.6
    ;;
  bar)
    sleep 0.6
    for n in 3 4 9 8 3; do focus "$n"; sleep 0.5; done
    for _ in 1 2 3; do omarchy-hyprland-workspace-layout-toggle >/dev/null; sleep 0.7; done
    ;;
  *) echo "unknown take: $1" >&2; exit 1 ;;
esac
