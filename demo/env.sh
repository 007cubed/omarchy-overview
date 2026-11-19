# Sourced by the demo scripts: reach the logged-in Hyprland session even over ssh.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)}

DEMO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$DEMO_DIR")
OUT_DIR=${DEMO_OUT:-$HOME/Videos/demo}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-overview-demo
mkdir -p "$OUT_DIR" "$STATE"

dispatch() { hyprctl dispatch "$1" >/dev/null; }
focus() { dispatch "o.workspaces.focus($1)"; sleep 0.3; }
carry() { dispatch "o.workspaces.move_window($1)"; sleep 0.3; }
overview() { omarchy-shell shell toggle guykawaii.overview '{}' >/dev/null; }
