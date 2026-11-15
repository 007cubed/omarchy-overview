import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

// Each workspace's layout, as Omarchy's workspace modes keep it: "dwindle"
// (tiling), "scrolling" or "floating". Read from the files Omarchy's layout
// commands write, one per workspace with a layout of its own, plus the default
// for the rest; one short script reads them all at once. Read again on
// reload() (the layout commands ask the bar, which passes it on to the
// overview; the overview also reads when it opens) and
// on a config reload. Also the theme's palette and each layout's colour.
Item {
  id: modes

  property var byId: ({})
  property string fallback: "dwindle"
  // Bumped after each read, for bindings that look modes up by function.
  property int revision: 0
  property bool again: false

  // Anything but Omarchy's three (a "master" default, say) counts as tiling.
  function known(m) { return m === "scrolling" || m === "floating" ? m : "dwindle" }

  function mode(id) {
    modes.revision
    var m = modes.byId[id]
    return modes.known(m ? m : modes.fallback)
  }

  // Tiling is never marked, whatever the default: only scrolling and floating are.
  function marked(id) { return modes.mode(id) !== "dwindle" }

  function reload() {
    if (read.running) {
      modes.again = true
      return
    }
    read.running = true
  }

  Component.onCompleted: reload()

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
      'm=$(sed -n \'s/.*default = "\\([a-z]*\\)".*/\\1/p\' "$d/default.lua" 2>/dev/null)\n' +
      '[[ -n $m ]] || m=$(hyprctl getoption general.layout -j 2>/dev/null | jq -r ".str // empty")\n' +
      'echo "default ${m:-dwindle}"\n' +
      'grep -Ho \'mode = "[a-z]*"\' "$d"/[0-9]*.lua 2>/dev/null | sed -E \'s#.*/([0-9]+)\\.lua:mode = "([a-z]+)"#\\1 \\2#\'']
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

  // ---- colour ---------------------------------------------------------------------

  // The theme's named colours (colors.toml). Omarchy pushes a theme switch to
  // the shell without reloading its own copy of the file, so this one is read
  // again whenever a core colour changes.
  property var palette: ({})

  FileView {
    id: colorsToml
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var p = {}
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (m) p[m[1].toLowerCase()] = m[2]
      }
      modes.palette = p
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { paletteReload.restart() }
    function onBackgroundChanged() { paletteReload.restart() }
    function onForegroundChanged() { paletteReload.restart() }
    function onUrgentChanged() { paletteReload.restart() }
  }
  Timer { id: paletteReload; interval: 0; onTriggered: colorsToml.reload() }

  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  // Too alike to tell apart at a glance: nearly the same colour, or the same
  // hue (within 25°) at similar lightness. Hue, not RGB distance: Tokyo Night's
  // magenta and blue accent are close in RGB but plainly different.
  function near(a, b) {
    var dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255
    if (Math.sqrt(dr * dr + dg * dg + db * db) < 40) return true
    if (a.hslSaturation < 0.15 || b.hslSaturation < 0.15) return false
    var dh = Math.abs(a.hslHue - b.hslHue) * 360
    dh = Math.min(dh, 360 - dh)
    return dh < 25 && Math.abs(a.hslLightness - b.hslLightness) < 0.25
  }
  function saturation(c) {
    var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b)
    var l = (mx + mn) / 2
    return mx === mn ? 0 : (mx - mn) / (1 - Math.abs(2 * l - 1))
  }

  // Green scrolls, magenta floats (the theme's named colours, else color2 / color5).
  function themeColor(mode) {
    var p = modes.palette
    if (mode === "scrolling") return p.green || p.color2 || ""
    if (mode === "floating") return p.magenta || p.color5 || ""
    return ""
  }

  // The layout's colour on `surface`, or `fallback` (that surface's ink). The
  // shape carries the meaning; colour only helps, so a colour that is grey,
  // under 3:1 on the surface, close to the accent ("current") or urgent
  // ("error"), or like the other layout's colour is left out.
  function color(mode, fallback, surface) {
    var hex = modes.themeColor(mode)
    if (!hex) return fallback
    var c = Qt.color(hex)
    if (modes.saturation(c) < 0.15) return fallback
    if (modes.contrast(c, surface) < 3) return fallback
    if (modes.near(c, Color.accent) || modes.near(c, Color.urgent)) return fallback
    // Two alike colours (retro-82's teals) would say nothing: both drop out.
    var other = modes.themeColor(mode === "scrolling" ? "floating" : "scrolling")
    if (other && modes.near(c, Qt.color(other))) return fallback
    return c
  }
}
