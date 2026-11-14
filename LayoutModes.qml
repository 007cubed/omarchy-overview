import QtQuick
import Quickshell.Hyprland
import qs.Commons
import Quickshell.Io

// Each workspace's layout, as Omarchy's workspace modes keep it: "dwindle"
// (tiling), "scrolling" or "floating". Read from the files Omarchy's layout
// commands write, one per workspace with a layout of its own, plus the default
// for the rest; one short script reads them all at once. Read again on
// reload() (the layout commands ask for it) and on a config reload.
Item {
  id: modes

  property var byId: ({})
  property string fallback: "dwindle"
  // Bumped after each read, for bindings that look modes up by function.
  property int revision: 0
  property bool again: false

  function mode(id) {
    modes.revision
    var m = modes.byId[id]
    return m ? m : modes.fallback
  }

  // Tiling is never marked, whatever the default: only scrolling and floating are.
  function marked(id) {
    var m = modes.mode(id)
    return m === "scrolling" || m === "floating"
  }

  // The theme's colour for each marked layout: green scrolls, magenta floats
  // (its named colours, else color2 / color5). The shape carries the meaning;
  // colour only helps, so one too faint on the background (under 3:1) falls
  // back to the foreground.
  property color scrollingColor: Color.foreground
  property color floatingColor: Color.foreground

  function color(mode, fallback) {
    if (mode === "scrolling") return modes.scrollingColor
    if (mode === "floating") return modes.floatingColor
    return fallback
  }

  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function readColors() {
    var text = Color.colorsFile ? String(Color.colorsFile.text() || "") : ""
    function pick(names) {
      for (var i = 0; i < names.length; i++) {
        var m = text.match(new RegExp("^\\s*" + names[i] + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m"))
        if (m) {
          var c = Qt.color(m[1])
          return modes.contrast(c, Color.background) >= 3 ? c : Color.foreground
        }
      }
      return Color.foreground
    }
    modes.scrollingColor = pick(["green", "color2"])
    modes.floatingColor = pick(["magenta", "color5"])
  }

  Connections {
    target: Color.colorsFile
    function onLoaded() { modes.readColors() }
  }

  function reload() {
    if (read.running) {
      modes.again = true
      return
    }
    read.running = true
  }

  Component.onCompleted: {
    reload()
    readColors()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") modes.reload()
    }
  }

  Process {
    id: read
    command: ["bash", "-c",
      'd="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts"\n' +
      'echo "default $(omarchy-hyprland-workspace-layout-default 2>/dev/null)"\n' +
      'for f in "$d"/*.lua; do n=${f##*/}; n=${n%.lua}; [[ $n =~ ^[0-9]+$ ]] || continue\n' +
      '  echo "$n $(sed -n \'s/.*mode = "\\([a-z]*\\)".*/\\1/p\' "$f")"; done']
    stdout: StdioCollector {
      onStreamFinished: {
        var next = {}
        var fallback = "dwindle"
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].trim().split(/\s+/)
          if (f.length < 2 || !f[1]) continue
          if (f[0] === "default") fallback = f[1]
          else next[parseInt(f[0], 10)] = f[1]
        }
        modes.fallback = fallback
        modes.byId = next
        modes.revision++
      }
    }
    onExited: {
      if (!modes.again) return
      modes.again = false
      Qt.callLater(modes.reload)
    }
  }
}
