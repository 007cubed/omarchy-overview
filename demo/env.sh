# Sourced by the demo scripts: reach the logged-in Hyprland session even over ssh,
# with the session's own environment (OMARCHY_PATH, PATH, the Hyprland instance).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
if [[ -z ${OMARCHY_PATH:-} ]]; then
  while IFS= read -r line; do
    case ${line%%=*} in
      OMARCHY_PATH | PATH | LANG | LC_* | WAYLAND_DISPLAY | HYPRLAND_INSTANCE_SIGNATURE | DBUS_SESSION_BUS_ADDRESS | XDG_CURRENT_DESKTOP)
        export "$line" ;;
    esac
  done < <(systemctl --user show-environment)
fi
export LANG=${LANG:-C.UTF-8}

DEMO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$DEMO_DIR")
OUT_DIR=${DEMO_OUT:-$HOME/Videos/demo}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-overview-demo
mkdir -p "$OUT_DIR" "$STATE"

dispatch() { hyprctl dispatch "$1" >/dev/null; }
focus() { dispatch "o.workspaces.focus($1)"; sleep 0.3; }
carry() { dispatch "o.workspaces.move_window($1)"; sleep 0.3; }
overview() { omarchy-shell shell toggle guykawaii.overview '{}' >/dev/null; }
