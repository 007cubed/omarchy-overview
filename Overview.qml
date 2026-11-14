import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Workspace overview for the focused monitor: its ten Omarchy workspace slots
// in a 5x2 grid with live window previews.
//   click a window      focus it and close
//   click a workspace   go there and close
//   drag a window       move it to the workspace it is dropped on
//   drag a number badge swap the whole workspace with the one it is dropped on,
//                       layouts intact (see swapSlots)
// A drag picks the neighbouring workspace in the direction it moves, after a
// fifth of a tile on each axis; dropped back near its start, it cancels. While
// dragging, the start tile has a dashed outline, the target a solid one, and the line under the
// grid says what the drop will do.
//                       (Super + drag anywhere too, when Hyprland lets Super through)
//   1-9, 0              go to that slot;  Esc closes
//   arrows / hjkl       move the selection (it starts on the current slot and
//                       follows the pointer);  Enter goes there
//   Shift + 1-9, 0      move the window under the pointer (or the selected
//                       slot's) to that slot, staying in the overview
// The line under the grid names what is under the pointer ("Go to 7",
// "firefox — title"), and the controls when nothing is.
// The pointer jumps to the current tile on open, back on a plain close, and to
// the focused window after going somewhere (see "pointer warps").
// Outside the overview, a switch to another workspace flashes a small 5x2 card
// at the bottom of the screen, "3 → 4" over the grid, with the highlight sliding
// from the old slot to the new one, so moving between rows reads as moving up or
// down. Carrying a window there also draws an arrow across the grid from the
// slot it left to the new one (a wrap such as 5 → 1 too, back across the row),
// and names the app under the grid. About 0.6 s.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  // Set when a click or key went somewhere, so closing leaves the pointer there
  // instead of putting it back where it was before the overview opened.
  property bool went: false
  // When the overview last closed; a switch it caused shows no hint.
  property real closedAt: 0

  readonly property int slots: 10
  readonly property int columns: 5
  readonly property int rows: Math.ceil(slots / columns)

  // Captured when the overview opens, so it stays on one monitor.
  property var monitor: null
  property string monitorName: ""
  property int block: 0
  property real monX: 0
  property real monY: 0
  property real monW: 1920
  property real monH: 1080
  // The monitor's scale. Tile edges and lines are snapped to whole screen
  // pixels with it, so at a fractional scale (1.6) a line or gap comes out the
  // same width on every side instead of rounding to 1 px here and 2 px there.
  property real dpr: 1
  function px(v) { return Math.round(v * root.dpr) / root.dpr }
  // A line at least one screen pixel wide.
  function line(v) { return Math.max(1, Math.round(v * root.dpr)) / root.dpr }
  readonly property real thinLine: line(Style.normalBorderWidth)
  readonly property real thickLine: line(Math.max(2, Style.normalBorderWidth * 2))

  // Bumped after Hyprland reports a change, so window geometry re-reads.
  property int revision: 0

  // Drag state, in stage coordinates.
  property string pressKind: ""
  property int pressSlot: -1
  property var pressToplevel: null
  property point pressPoint: Qt.point(0, 0)
  property point pressOffset: Qt.point(0, 0)
  property point dragPoint: Qt.point(0, 0)
  property size dragSize: Qt.size(0, 0)
  property bool dragging: false
  property int hoverSlot: -1
  // Keyboard selection and what the pointer is over, outside a drag. `keyed`
  // says the keys moved the selection last, so it, not the pointer, is named.
  property int selectedSlot: -1
  property int pointSlot: -1
  property var pointToplevel: null
  // The pointer is on pointSlot's number badge.
  property bool pointBadge: false
  property bool keyed: false
  property real hoverHoldUntil: 0
  // Super as seen through key events; pointer modifiers may not carry it.
  property bool superHeld: false

  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property int radius: Style.cornerRadius
  readonly property int gap: Style.spacing.md * 2
  readonly property string fontFamily: Style.font.menuFamily

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---- shell plugin contract ------------------------------------------------

  function open(payloadJson) {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.captureMonitor()
    root.resetPress()
    root.superHeld = false
    root.went = false
    root.selectedSlot = Math.max(1, root.activeSlot())
    root.pointSlot = -1
    root.pointToplevel = null
    root.keyed = false
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (root.opened && !root.went) root.restoreCursor()
    root.opened = false
    root.closedAt = Date.now()
    root.resetPress()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "guykawaii.overview")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---- Hyprland state ---------------------------------------------------------

  function captureMonitor() {
    var m = Hyprland.focusedMonitor
    root.monitor = m
    root.monitorName = m ? String(m.name || "") : ""
    var ws = m ? m.activeWorkspace : null
    root.block = ws && ws.id > 0 ? Math.floor((ws.id - 1) / root.slots) : 0

    var ipc = m ? m.lastIpcObject : null
    if (ipc && ipc.width > 0 && ipc.height > 0) {
      var scale = ipc.scale > 0 ? ipc.scale : 1
      root.dpr = scale
      var rotated = (ipc.transform || 0) % 2 === 1
      root.monX = ipc.x || 0
      root.monY = ipc.y || 0
      root.monW = (rotated ? ipc.height : ipc.width) / scale
      root.monH = (rotated ? ipc.width : ipc.height) / scale
    }
  }

  function workspaceId(slot) {
    return root.block * root.slots + slot
  }

  function activeSlot() {
    var ws = root.monitor ? root.monitor.activeWorkspace : null
    if (!ws || ws.id < 1 || Math.floor((ws.id - 1) / root.slots) !== root.block) return -1
    return (ws.id - 1) % root.slots + 1
  }

  // The slot (1-10) a window's workspace is in, or -1 if it is on another block.
  function slotOf(toplevel) {
    var ws = toplevel ? toplevel.workspace : null
    if (!ws || ws.id < 1 || Math.floor((ws.id - 1) / root.slots) !== root.block) return -1
    return (ws.id - 1) % root.slots + 1
  }

  // Visible windows on a slot; floating ones last so they draw on top.
  function windowsIn(slot) {
    var rev = root.revision
    var id = root.workspaceId(slot)
    var tiled = []
    var floating = []
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if (!t.workspace || t.workspace.id !== id) continue
      var ipc = t.lastIpcObject
      if (!ipc || !ipc.at || !ipc.size || ipc.hidden) continue
      if (ipc.floating) floating.push(t)
      else tiled.push(t)
    }
    return tiled.concat(floating)
  }

  // Quickshell gives addresses without the 0x Hyprland expects; "" if malformed.
  function addressOf(toplevel) {
    var address = String((toplevel && toplevel.address) || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    return /^0x[0-9a-fA-F]+$/.test(address) ? address : ""
  }

  function moveWindow(toplevel, slot) {
    var address = root.addressOf(toplevel)
    if (!address) return
    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + root.workspaceId(slot)
      + '", follow = false, window = "address:' + address + '" })')
  }

  // Swaps two workspaces by trading their ids, so each keeps its windows, split
  // tree, sizes, floating positions and fullscreen untouched; nothing re-tiles.
  // Hyprland only gives a workspace a free id, so one passes through a spare id
  // above all others. All three changes run in one chunk, before Hyprland's
  // deferred refresh, so the persistent slot rules never see a slot missing.
  // The screen stays as it is: if the current workspace is one of the two, it
  // goes along to its new slot. A slot that does not exist just takes the id.
  function swapSlots(a, b) {
    var idA = root.workspaceId(a)
    var idB = root.workspaceId(b)
    Hyprland.dispatch('function() '
      + 'local function change(from, to) hl.dispatch(hl.dsp.workspace.change_id({ workspace = tostring(from), id = to })) end; '
      + 'local a, b = hl.get_workspace("' + idA + '"), hl.get_workspace("' + idB + '"); '
      + 'if a and b then '
      + 'local spare = 0; for _, w in ipairs(hl.get_workspaces()) do if w.id > spare then spare = w.id end end; '
      + 'spare = spare + 1; '
      + 'change(' + idA + ', spare); change(' + idB + ', ' + idA + '); change(spare, ' + idB + ') '
      + 'elseif a then change(' + idA + ', ' + idB + ') '
      + 'elseif b then change(' + idB + ', ' + idA + ') end end')
  }

  // ---- pointer warps ------------------------------------------------------------
  // On open the pointer jumps to the current workspace's tile; closing without
  // going anywhere puts it back, and going somewhere leaves it on the window that
  // got focus (or the monitor's centre), so follow_mouse keeps that focus.
  // hl.dsp.cursor.move ignores cursor:no_warps, so each chunk checks it first.
  readonly property string noWarps: 'if hl.get_config("cursor:no_warps") then return end; '
  // While the overview holds the keyboard the focus may not have moved yet, so
  // the workspace's last focused window stands in.
  readonly property string warpToFocus: 'local m = hl.get_active_monitor(); '
    + 'local ws = m and m.active_workspace; '
    + 'local w = hl.get_active_window(); '
    + 'if not (w and w.workspace and ws and w.workspace.id == ws.id) then w = ws and ws.last_window end; '
    + 'if w then '
    + 'hl.dispatch(hl.dsp.cursor.move({ x = w.at.x + w.size.x / 2, y = w.at.y + w.size.y / 2 })) '
    + 'elseif m then hl.dispatch(hl.dsp.cursor.move({ x = m.x + m.width / m.scale / 2, y = m.y + m.height / m.scale / 2 })) end'

  function warpToTile(slot) {
    if (slot < 1) return
    var x = Math.round(root.monX + root.tileX(slot) + stage.tileW / 2)
    var y = Math.round(root.monY + root.tileY(slot) + stage.tileH / 2)
    Hyprland.dispatch('function() ' + root.noWarps + '_G.ovCursor = hl.get_cursor_pos(); '
      + 'hl.dispatch(hl.dsp.cursor.move({ x = ' + x + ', y = ' + y + ' })) end')
    // The layer gets no motion from a warp, and while the stage zooms in Qt
    // replays hover at the pointer's old place, so hover starts from where the
    // warp lands and ignores the pointer until the zoom is over.
    root.hoverHoldUntil = Date.now() + Style.duration(120) + 150
    root.hoverAt(Qt.point(root.tileX(slot) + stage.tileW / 2, root.tileY(slot) + stage.tileH / 2))
  }

  function restoreCursor() {
    Hyprland.dispatch('function() local p = _G.ovCursor; _G.ovCursor = nil; ' + root.noWarps
      + 'if p then hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end end')
  }

  // A go: the focus dispatch and the warp in one chunk, so the warp sees the
  // focus it caused.
  function go(focus) {
    root.went = true
    Hyprland.dispatch('function() _G.ovCursor = nil; hl.dispatch(' + focus + '); '
      + root.noWarps + root.warpToFocus + ' end')
  }

  function focusSlot(slot) {
    if (/^[A-Za-z0-9._-]+$/.test(root.monitorName))
      root.go('o.workspaces.focus(' + slot + ', "' + root.monitorName + '")')
    else
      root.go('hl.dsp.focus({ workspace = "' + root.workspaceId(slot) + '" })')
  }

  function focusWindow(toplevel) {
    var address = root.addressOf(toplevel)
    if (!address) return
    root.go('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  // Only events that move, add or remove windows change the previews; focus,
  // title and layout events would only cause needless refreshes.
  readonly property var refreshEvents: ({
    openwindow: true, closewindow: true, movewindow: true, movewindowv2: true,
    changefloatingmode: true, fullscreen: true, pin: true,
    workspace: true, workspacev2: true, createworkspace: true, createworkspacev2: true,
    destroyworkspace: true, destroyworkspacev2: true, moveworkspace: true, moveworkspacev2: true,
    changeworkspaceid: true
  })

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.opened && event && root.refreshEvents[String(event.name)]) refreshTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 60
    onTriggered: {
      // A swap renumbers workspaces, which moves the active-slot ring too.
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 60
    onTriggered: {
      if (root.pressKind) restart()
      else root.revision++
    }
  }

  // ---- pointer handling ---------------------------------------------------------

  function resetPress() {
    root.pressKind = ""
    root.pressSlot = -1
    root.pressToplevel = null
    root.dragging = false
    root.hoverSlot = -1
  }

  // The window preview under a stage point, topmost first, or null.
  function windowAt(slot, p) {
    var best = null
    for (var i = 0; i < previews.count; i++) {
      var frame = previews.itemAt(i)
      if (!frame || !frame.visible || frame.slot !== slot) continue
      var w = frame.preview
      var q = stage.mapToItem(w, p.x, p.y)
      if (q.x < 0 || q.y < 0 || q.x > w.width || q.y > w.height) continue
      if (!best || frame.z >= best.z) best = w
    }
    return best
  }

  // withSuper: Super held, so the press takes the whole workspace.
  function beginPress(p, withSuper) {
    root.resetPress()
    var slot = root.slotAt(p)
    if (slot < 1) {
      root.pressKind = "backdrop"
      return
    }
    var tile = tiles.itemAt(slot - 1)
    var wholeWorkspace = withSuper || root.onBadge(slot, p)
    var win = wholeWorkspace ? null : root.windowAt(slot, p)
    var item = win || tile
    var local = stage.mapToItem(item, p.x, p.y)
    // Without Super, empty tile space only clicks; it has nothing to drag.
    root.pressKind = win ? "window" : (wholeWorkspace ? "workspace" : "slot")
    root.pressSlot = slot
    root.pressToplevel = win ? win.modelData : null
    root.pressPoint = p
    root.pressOffset = Qt.point(local.x, local.y)
    root.dragPoint = p
    root.dragSize = Qt.size(item.width, item.height)
  }

  function movePress(p) {
    if (!root.pressKind || root.pressKind === "backdrop" || root.pressKind === "slot") return
    root.dragPoint = p
    if (!root.dragging && Math.hypot(p.x - root.pressPoint.x, p.y - root.pressPoint.y) > 8)
      root.dragging = true
    if (root.dragging) root.hoverSlot = root.dropSlot()
  }

  // Whether p (stage coordinates) is on slot's number badge, the workspace handle.
  function onBadge(slot, p) {
    var badge = badges.itemAt(slot - 1)
    var b = stage.mapToItem(badge, p.x, p.y)
    return b.x >= 0 && b.y >= 0 && b.x <= badge.width && b.y <= badge.height
  }

  // Hover, outside a press: the selection follows the pointer. The badge sits
  // over the windows, so on it the pointer means the workspace, not a window.
  function hoverAt(p) {
    var slot = root.slotAt(p)
    root.pointSlot = slot
    root.pointBadge = slot > 0 && root.onBadge(slot, p)
    root.pointToplevel = slot > 0 && !root.pointBadge ? (root.windowAt(slot, p) || {}).modelData || null : null
    if (slot > 0) {
      root.selectedSlot = slot
      root.keyed = false
    }
  }

  function clearPoint() {
    root.pointSlot = -1
    root.pointBadge = false
    root.pointToplevel = null
  }

  // Arrows and hjkl step the selection around the grid, stopping at its edges.
  function moveSelection(dx, dy) {
    var slot = Math.max(1, root.selectedSlot)
    var col = Math.max(0, Math.min(root.columns - 1, (slot - 1) % root.columns + dx))
    var row = Math.max(0, Math.min(root.rows - 1, Math.floor((slot - 1) / root.columns) + dy))
    root.selectedSlot = row * root.columns + col + 1
    root.pointToplevel = null
    root.keyed = true
  }

  // Shift + number: the window under the pointer, else the selected slot's
  // focused window, else its first one.
  function moveTarget() {
    if (root.pointToplevel && !root.keyed) return root.pointToplevel
    var active = Hyprland.activeToplevel
    if (active && root.slotOf(active) === root.selectedSlot) return active
    var list = root.windowsIn(root.selectedSlot)
    return list.length > 0 ? list[0] : null
  }

  // The slot of a Shift + number key: by its place on the number row (evdev
  // 2-11, +8 on Wayland), since Shift turns the digits into whatever the layout
  // puts there, or by the digit when it stays one.
  function shiftedSlot(event) {
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) return event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0
    return event.nativeScanCode >= 10 && event.nativeScanCode <= 19 ? event.nativeScanCode - 9 : -1
  }

  // The line under the grid.
  function statusText() {
    if (root.dragging) return root.dragText()
    var t = root.keyed ? null : root.pointToplevel
    if (t) {
      var ipc = t.lastIpcObject
      var name = String((ipc && ipc["class"]) || "")
      var title = String(t.title || "")
      return name && title && name !== title ? strings.t("status.window").arg(name).arg(title) : (title || name)
    }
    if (root.pointBadge && !root.keyed) return strings.t("status.handle").arg(root.pointSlot % 10)
    var slot = root.keyed ? root.selectedSlot : root.pointSlot
    return slot > 0 ? strings.t("status.go").arg(slot % 10) : strings.t("hint")
  }

  function endPress(p) {
    var kind = root.pressKind
    var from = root.pressSlot
    var toplevel = root.pressToplevel
    var wasDrag = root.dragging
    var target = wasDrag ? root.dropSlot() : -1
    root.resetPress()

    if (!kind) return
    if (kind === "backdrop") {
      root.dismiss()
      return
    }
    if (!wasDrag) {
      if (kind === "window") root.focusWindow(toplevel)
      else root.focusSlot(from)
      root.dismiss()
      return
    }
    if (kind === "slot" || target < 1 || target === from) return
    if (kind === "window") root.moveWindow(toplevel, target)
    else root.swapSlots(from, target)
  }

  // Tile geometry is plain grid arithmetic in stage coordinates.
  function tileX(slot) { return root.px(stage.gridX + ((slot - 1) % root.columns) * (stage.tileW + root.gap)) }
  function tileY(slot) { return root.px(stage.gridY + Math.floor((slot - 1) / root.columns) * (stage.tileH + root.gap)) }

  // The tile under a point, or -1 on a gap or outside the grid.
  function slotAt(p) {
    var x = p.x - stage.gridX
    var y = p.y - stage.gridY
    if (x < 0 || y < 0 || x > stage.gridW || y > stage.gridH) return -1
    var col = Math.floor(x / (stage.tileW + root.gap))
    var row = Math.floor(y / (stage.tileH + root.gap))
    if (x - col * (stage.tileW + root.gap) > stage.tileW) return -1
    if (y - row * (stage.tileH + root.gap) > stage.tileH) return -1
    var slot = row * root.columns + col + 1
    return slot <= root.slots ? slot : -1
  }

  // Where a drag would land, from how far it has moved: measured in tile steps
  // per axis (tile width across, tile height down, so a diagonal costs the same
  // both ways), and any clear movement counts. A fifth of a step picks the
  // neighbour on that side; dropping it back near its start cancels. Past the
  // grid's edge it stays on the last tile.
  readonly property real dropThreshold: 0.2

  function dropSlot() {
    if (root.pressSlot < 1) return -1
    function steps(distance, size) {
      var n = Math.abs(distance) / (size + root.gap)
      return n < root.dropThreshold ? 0 : Math.sign(distance) * Math.ceil(n - root.dropThreshold)
    }
    var col = (root.pressSlot - 1) % root.columns + steps(root.dragPoint.x - root.pressPoint.x, stage.tileW)
    var row = Math.floor((root.pressSlot - 1) / root.columns) + steps(root.dragPoint.y - root.pressPoint.y, stage.tileH)
    col = Math.max(0, Math.min(root.columns - 1, col))
    row = Math.max(0, Math.min(root.rows - 1, row))
    var slot = row * root.columns + col + 1
    return slot <= root.slots ? slot : -1
  }

  // What a drag will do, for the line under the grid: "Move firefox: 2 → 7" or
  // "Swap 2 ↔ 7". Over its own tile the target is "…" (dropping there cancels).
  function dragText() {
    var from = String(root.pressSlot % 10)
    var to = root.hoverSlot > 0 && root.hoverSlot !== root.pressSlot ? String(root.hoverSlot % 10) : "…"
    if (root.pressKind === "workspace") return strings.t("drag.swap").arg(from).arg(to)
    var ipc = root.pressToplevel ? root.pressToplevel.lastIpcObject : null
    var name = String((ipc && ipc["class"]) || (root.pressToplevel && root.pressToplevel.title) || "")
    return strings.t("drag.move").arg(name).arg(from).arg(to)
  }

  // ---- UI -----------------------------------------------------------------------

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "guykawaii-overview"

    // Once the layer is on screen, so the pointer lands on a drawn tile.
    onContentRevealedChanged: if (contentRevealed && root.opened) root.warpToTile(root.activeSlot())

    // Dim the desktop well enough that the tiles and hint read clearly.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.88)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta)
          root.superHeld = false
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
          root.superHeld = true
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if ((event.modifiers & Qt.ShiftModifier) && root.shiftedSlot(event) > 0) {
          var target = root.moveTarget()
          if (target) root.moveWindow(target, root.shiftedSlot(event))
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.selectedSlot > 0) root.focusSlot(root.selectedSlot)
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.moveSelection(-1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
          root.moveSelection(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveSelection(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveSelection(0, 1)
          event.accepted = true
        } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
          var slot = event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0
          root.focusSlot(slot)
          root.dismiss()
          event.accepted = true
        }
      }
    }

    Item {
      id: stage
      anchors.fill: parent

      readonly property real availW: width - root.gap * 4
      // The status line's height comes from the font, not its text, so the
      // grid never moves when the line changes (a title's glyphs from a
      // fallback font would otherwise make it taller).
      readonly property real statusH: Math.ceil(statusMetrics.height)
      readonly property real availH: height - root.gap * 6 - statusH
      readonly property real aspect: root.monH / Math.max(1, root.monW)
      readonly property real tileW: root.px(Math.max(40, Math.min(
        (availW - root.gap * (root.columns - 1)) / root.columns,
        ((availH - root.gap * (root.rows - 1)) / root.rows) / aspect)))
      readonly property real tileH: root.px(tileW * aspect)
      readonly property real tileScale: tileW / Math.max(1, root.monW)
      readonly property real gridW: root.columns * tileW + (root.columns - 1) * root.gap
      readonly property real gridH: root.rows * tileH + (root.rows - 1) * root.gap
      readonly property real gridX: root.px((width - gridW) / 2)
      readonly property real gridY: root.px((height - gridH) / 2 - statusH / 2)

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      // Tile backgrounds. Previews, badges and outlines are separate layers above
      // them, so there is one preview per window rather than one per window per
      // tile, and the outlines run unbroken over the corner badges.
      Repeater {
        id: tiles
        model: root.slots

        delegate: Rectangle {
          id: tile
          required property int index
          readonly property int slot: index + 1
          readonly property bool active: root.activeSlot() === slot
          readonly property bool target: root.dragging && root.hoverSlot === slot && root.pressSlot !== slot
          // Where a drag started: a darker hole, outlined by dragOrigin above it.
          readonly property bool origin: root.dragging && root.pressSlot === slot
          // Where Enter goes: shown while the pointer is on a tile or the keys moved it.
          readonly property bool selected: !root.dragging && root.selectedSlot === slot && (root.keyed || root.pointSlot > 0)

          x: root.tileX(slot)
          y: root.tileY(slot)
          width: stage.tileW
          height: stage.tileH
          radius: root.radius
          color: target || selected ? root.selectedBackground : (origin ? Qt.darker(root.background, 1.4) : root.background)
        }
      }

      // One live preview per Hyprland window, placed in its workspace's tile.
      // Bound to the live window list rather than a filtered array, so title
      // changes don't rebuild delegates (and cancel a drag).
      Repeater {
        id: previews
        model: Hyprland.toplevels

        delegate: Item {
          id: frame
          required property var modelData
          readonly property var ipc: { root.revision; return modelData.lastIpcObject || {} }
          readonly property int slot: root.slotOf(modelData)
          readonly property bool shown: slot > 0 && !!ipc.at && !!ipc.size && !ipc.hidden
          readonly property bool lifted: root.dragging && root.pressToplevel === modelData && root.pressKind === "window"
          readonly property bool tileLifted: root.dragging && root.pressKind === "workspace" && root.pressSlot === slot
          property alias preview: win

          visible: shown
          z: ipc.floating ? 2 : 1
          x: slot > 0 ? root.tileX(slot) : 0
          y: slot > 0 ? root.tileY(slot) : 0
          width: stage.tileW
          height: stage.tileH
          clip: true
          opacity: tileLifted ? 0.4 : 1

          Rectangle {
            id: win
            readonly property var modelData: frame.modelData
            x: ((frame.ipc.at ? frame.ipc.at[0] : 0) - root.monX) * stage.tileScale
            y: ((frame.ipc.at ? frame.ipc.at[1] : 0) - root.monY) * stage.tileScale
            width: Math.max(8, (frame.ipc.size ? frame.ipc.size[0] : 0) * stage.tileScale)
            height: Math.max(8, (frame.ipc.size ? frame.ipc.size[1] : 0) * stage.tileScale)
            radius: Math.max(2, root.radius / 2)
            color: Qt.darker(root.background, 1.25)
            border.width: 1
            border.color: Commons.Color.menu.border
            clip: true
            opacity: frame.lifted ? 0.3 : 1

            ScreencopyView {
              anchors.fill: parent
              anchors.margins: 1
              captureSource: root.opened && frame.shown ? frame.modelData.wayland : null
              // Paused while a whole workspace is dragged: its copy shows only the number.
              live: root.opened && !(root.dragging && root.pressKind === "workspace")
            }

            Text {
              textFormat: Text.PlainText
              visible: !frame.modelData.wayland
              anchors.centerIn: parent
              width: parent.width - Style.space(6)
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: String(frame.ipc["class"] || frame.modelData.title || "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }

      // A drag's start and target, outlined above the previews so windows don't
      // hide them: a dashed outline where it came from, a solid one where it goes.
      Shape {
        id: dragOrigin
        readonly property real inset: lineWidth / 2
        readonly property real lineWidth: root.thickLine
        visible: root.dragging && root.pressSlot > 0
        z: 4
        x: root.pressSlot > 0 ? root.tileX(root.pressSlot) : 0
        y: root.pressSlot > 0 ? root.tileY(root.pressSlot) : 0
        width: stage.tileW
        height: stage.tileH
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: root.accent
          strokeWidth: dragOrigin.lineWidth
          strokeStyle: ShapePath.DashLine
          dashPattern: [4, 3]
          fillColor: "transparent"
          PathRectangle {
            x: dragOrigin.inset
            y: dragOrigin.inset
            width: dragOrigin.width - dragOrigin.lineWidth
            height: dragOrigin.height - dragOrigin.lineWidth
            radius: root.radius
          }
        }
      }

      Rectangle {
        visible: root.dragging && root.hoverSlot > 0 && root.hoverSlot !== root.pressSlot
        z: 4
        x: visible ? root.tileX(root.hoverSlot) : 0
        y: visible ? root.tileY(root.hoverSlot) : 0
        width: stage.tileW
        height: stage.tileH
        radius: root.radius
        color: "transparent"
        border.width: dragOrigin.lineWidth
        border.color: root.accent
      }

      // A badge under the pointer tints its whole tile (the selection ring is
      // already round it): grabbing the badge carries the workspace, not one
      // window. Drawn over the previews, so nothing under it moves or resizes.
      Rectangle {
        id: handleTint
        readonly property int slot: !root.keyed && !root.dragging && root.pointBadge ? root.pointSlot : -1
        visible: slot > 0
        z: 2.5
        x: visible ? root.tileX(slot) : 0
        y: visible ? root.tileY(slot) : 0
        width: stage.tileW
        height: stage.tileH
        radius: root.radius
        color: Util.alpha(root.accent, 0.12)
      }

      // Slot numbers, in each tile's bottom-left corner: the handle for dragging a workspace.
      Repeater {
        id: badges
        model: root.slots

        delegate: Rectangle {
          id: badge
          required property int index
          readonly property int slot: index + 1
          readonly property bool active: root.activeSlot() === slot
          // Hovered, or being dragged: the handle shows itself.
          readonly property bool lit: !root.keyed && root.pointBadge && root.pointSlot === slot
                                      || root.dragging && root.pressKind === "workspace" && root.pressSlot === slot

          z: 3
          // Flush in the tile's corner; it shares the tile's rounding there.
          x: root.tileX(slot)
          y: root.tileY(slot) + stage.tileH - height
          width: Math.max(height, label.implicitWidth + Style.spacing.md * 2)
          height: label.implicitHeight + Style.spacing.sm * 2
          radius: root.radius
          color: active ? root.accent : Util.alpha(root.background, lit ? 0.95 : 0.75)
          border.width: lit ? Math.max(1, Style.normalBorderWidth) : 0
          border.color: active ? root.foreground : root.accent

          Text {
            id: label
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: String(badge.slot % 10)
            color: badge.active ? root.background : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }
      }

      // Tile outlines, over the previews and badges: accent for the current
      // workspace and a drop target.
      Repeater {
        model: root.slots

        delegate: Rectangle {
          required property int index
          readonly property int slot: index + 1
          readonly property bool strong: root.activeSlot() === slot
                                         || root.dragging && root.hoverSlot === slot && root.pressSlot !== slot
          z: 3.5
          x: root.tileX(slot)
          y: root.tileY(slot)
          width: stage.tileW
          height: stage.tileH
          radius: root.radius
          color: "transparent"
          border.width: strong ? root.thickLine : root.thinLine
          border.color: strong ? root.accent : Commons.Color.menu.border
        }
      }

      // Where Enter goes, by pointer or arrow keys: a ring just outside the tile.
      // The tile's own background is mostly hidden under its previews, and a ring
      // apart from the edge can't be mistaken for the current workspace's outline.
      Rectangle {
        readonly property int slot: !root.dragging && (root.keyed || root.pointSlot > 0) ? root.selectedSlot : -1
        // Ring width plus an even gap to the tile's edge.
        readonly property real offset: root.thickLine + root.line(2)
        visible: slot > 0
        z: 4
        x: visible ? root.tileX(slot) - offset : 0
        y: visible ? root.tileY(slot) - offset : 0
        width: stage.tileW + offset * 2
        height: stage.tileH + offset * 2
        radius: root.radius > 0 ? root.radius + offset : 0
        color: "transparent"
        border.width: root.thickLine
        border.color: root.foreground
      }

      FontMetrics {
        id: statusMetrics
        font: hint.font
      }

      // One line of fixed height and width, elided; centred text, so only the
      // text itself changes.
      Text {
        id: hint
        textFormat: Text.PlainText
        x: root.gap
        y: stage.gridY + stage.gridH + root.gap
        width: stage.width - root.gap * 2
        height: stage.statusH
        maximumLineCount: 1
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.statusText()
        color: root.foreground
        opacity: text === strings.t("hint") ? 0.7 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // All clicks and drags go through here, so a drag survives previews
      // being refreshed underneath it.
      MouseArea {
        anchors.fill: parent
        z: 50
        preventStealing: true
        hoverEnabled: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : root.pointBadge ? Qt.OpenHandCursor : Qt.ArrowCursor
        onPressed: function(mouse) {
          root.beginPress(Qt.point(mouse.x, mouse.y), root.superHeld || (mouse.modifiers & Qt.MetaModifier) !== 0)
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.movePress(Qt.point(mouse.x, mouse.y))
          else if (Date.now() >= root.hoverHoldUntil) root.hoverAt(Qt.point(mouse.x, mouse.y))
        }
        onExited: root.clearPoint()
        onReleased: function(mouse) { root.endPress(Qt.point(mouse.x, mouse.y)) }
        onCanceled: root.resetPress()
      }

      // What is being dragged, following the pointer.
      Rectangle {
        id: ghost
        visible: root.dragging
        z: 100
        x: root.dragPoint.x - root.pressOffset.x
        y: root.dragPoint.y - root.pressOffset.y
        width: root.dragSize.width
        height: root.dragSize.height
        radius: root.radius
        color: root.pressKind === "workspace" ? Util.alpha(root.background, 0.5) : root.background
        border.width: Math.max(2, Style.normalBorderWidth * 2)
        border.color: root.accent
        clip: true
        opacity: 0.9

        ScreencopyView {
          anchors.fill: parent
          anchors.margins: 2
          visible: root.pressKind === "window"
          captureSource: root.dragging && root.pressToplevel ? root.pressToplevel.wayland : null
          live: root.dragging
        }

        Text {
          textFormat: Text.PlainText
          visible: root.pressKind === "workspace"
          anchors.centerIn: parent
          text: String(root.pressSlot % 10)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
        }
      }
    }
  }

  // ---- switch hint ----------------------------------------------------------------

  // The slot the hint slides from and to, and the block of ten it shows.
  property int hintFrom: -1
  property int hintTo: -1
  property int hintBlock: 0
  // Seeded at start, so the first switch after a shell restart has a "from".
  property int lastWorkspaceId: -1
  Component.onCompleted: root.lastWorkspaceId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  // hintMapped keeps the window up while the card fades out after hintShown.
  property bool hintShown: false
  property bool hintMapped: false
  // A carry (4 fingers sideways, Super + Shift + number): an arrow from the
  // slot the window left, and its app icon and name under the grid.
  property bool hintCarry: false
  property string hintText: ""
  property string hintApp: ""
  property string hintIcon: ""
  property string hintLetter: ""
  // The last movewindowv2: Hyprland sends it just before the workspacev2 of a
  // move that follows its window.
  property var lastMove: null

  // ---- level hint ---------------------------------------------------------------
  // The same card after a window changes level: 0 tiled, 1 floating, 2 popped
  // (pinned on every workspace). Three cells instead of the grid, the new level
  // as the label, one arrow from the old cell, the app under it.
  property bool hintLevel: false
  property int levelFrom: 0
  property int levelTo: 0
  // address -> { floating, pinned }, kept from Hyprland's events; a window not
  // seen yet starts from its last known state.
  property var levelState: ({})
  // The level a burst of events started from: a pop sends float and pin a few
  // ms apart, and the card shows the burst as one step.
  property var levelPending: null

  function levelOf(state) { return state.pinned ? 2 : state.floating ? 1 : 0 }

  function noteLevelEvent(address, key, value) {
    var state = root.levelState[address]
    if (!state) {
      var ipc = (root.toplevelByAddress(address) || {}).lastIpcObject
      state = { floating: !!(ipc && ipc.floating), pinned: !!(ipc && ipc.pinned) }
    }
    if (!root.levelPending || root.levelPending.address !== address)
      root.levelPending = { address: address, from: root.levelOf(state) }
    state[key] = value
    root.levelState[address] = state
    levelSettle.restart()
  }

  function showLevel(address, from, to) {
    if (from === to) return
    var toplevel = root.toplevelByAddress(address)
    // Only the window being worked on: a rule floating some other window
    // somewhere stays quiet.
    var active = Hyprland.activeToplevel
    if (!toplevel || !active || String(active.address).replace(/^0x/, "") !== address) return
    if (root.opened || Date.now() - root.closedAt < 300) return

    var app = root.appOf(toplevel)
    var fresh = !root.hintMapped
    root.hintLevel = true
    root.hintCarry = false
    root.levelFrom = from
    root.levelTo = to
    root.hintIcon = app.icon
    root.hintLetter = app.name ? app.name.charAt(0).toUpperCase() : ""
    root.hintApp = app.name.length > 9 ? app.name.slice(0, 8) + "…" : app.name
    root.hintText = strings.t(["level.tiled", "level.floating", "level.popped"][to])
    root.hintMapped = true
    root.hintShown = true
    hintHold.interval = Style.duration(120) + 530
    hintHold.restart()
    hintUnmap.stop()
    if (fresh) hintCard.placeLevel(from)
    else hintCard.slideLevel(to)
  }

  Timer {
    id: levelSettle
    interval: 80
    onTriggered: {
      var pending = root.levelPending
      root.levelPending = null
      if (!pending) return
      var state = root.levelState[pending.address]
      if (state) root.showLevel(pending.address, pending.from, root.levelOf(state))
    }
  }

  // ---- carry arrow colour ------------------------------------------------------
  // Set in Omarchy's shell.toml, the theme's or ~/.config/omarchy/shell.toml (which
  // survives theme switches):
  //   [overview]
  //   carry-arrow = "green"   # a colors.toml name, a role (accent, text, urgent,
  //                           # muted) or "#rrggbb"; unset = the theme's foreground
  // The default is the foreground: of every theme colour it is the only one that
  // keeps WCAG 3:1 against the card and the stepped-back cells in all stock themes
  // (worst: everforest, 3.75:1). Accent, green and the rest fail in 4 or more.
  // Omarchy's Color only keeps the core roles, so names like "green" are looked
  // up in the theme's colors.toml, read again whenever the theme changes.
  property var themePalette: ({})
  readonly property color carryArrowColor: {
    var fallback = Commons.Color.foreground
    var value = String(Commons.Color.pick("overview.carry-arrow", "")).trim()
    if (!value) return fallback
    var name = value.toLowerCase()
    var core = ["accent", "foreground", "text", "urgent", "muted", "background"]
    if (value.charAt(0) !== "#" && core.indexOf(name) < 0)
      return root.themePalette[name] || fallback
    return Commons.Color.flatColor(value, fallback)
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var palette = {}
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (match) palette[match[1].toLowerCase()] = match[2]
      }
      root.themePalette = palette
    }
  }

  // A theme switch changes the accent; read the new theme's palette then.
  Connections {
    target: Commons.Color
    function onAccentChanged() { themeColorsFile.reload() }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function toplevelByAddress(address) {
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      if (String(all[i].address).replace(/^0x/, "") === address) return all[i]
    }
    return null
  }

  // The window's app name and icon URL ("" when the theme has none).
  function appOf(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var appId = String((ipc && ipc["class"]) || (toplevel && toplevel.wayland && toplevel.wayland.appId) || "")
    var entry = appId ? DesktopEntries.heuristicLookup(appId) : null
    var icon = entry && entry.icon ? String(entry.icon) : ""
    return {
      name: appId || String((toplevel && toplevel.title) || ""),
      icon: icon.charAt(0) === "/" ? "file://" + icon : (icon ? Quickshell.iconPath(icon, true) : "")
    }
  }

  function showSwitch(id) {
    var previous = root.lastWorkspaceId
    root.lastWorkspaceId = id
    var move = root.lastMove
    root.lastMove = null
    if (id < 1 || id === previous) return
    // The overview shows the move itself, and a fullscreen window wants the screen.
    if (root.opened || Date.now() - root.closedAt < 300) return
    var ws = root.workspaceById(id)
    if (ws && ws.hasFullscreen) return

    var block = Math.floor((id - 1) / root.slots)
    var to = (id - 1) % root.slots + 1
    // From another block (another monitor's) there is nothing to slide from.
    var from = previous > 0 && Math.floor((previous - 1) / root.slots) === block
      ? (previous - 1) % root.slots + 1 : to
    var carry = !!move && move.id === id && Date.now() - move.time < 150
    var app = carry ? root.appOf(root.toplevelByAddress(move.address)) : null
    var fresh = !root.hintMapped

    root.hintLevel = false
    root.hintBlock = block
    root.hintFrom = from
    root.hintTo = to
    root.hintCarry = carry
    root.hintIcon = app ? app.icon : ""
    root.hintLetter = app && app.name ? app.name.charAt(0).toUpperCase() : ""
    // Short enough to read at a glance: at most 9 characters.
    root.hintApp = !app ? "" : app.name.length > 9 ? app.name.slice(0, 8) + "…" : app.name
    root.hintText = from === to ? String(to % 10) : strings.t("switch.go").arg(from % 10).arg(to % 10)
    root.hintMapped = true
    root.hintShown = true
    // Long enough to read, short enough to be gone before the next look; a
    // carry has a name to read, so it stays a little longer.
    hintHold.interval = Style.duration(120) + (carry ? 530 : 380)
    hintHold.restart()
    hintUnmap.stop()
    // A fresh card waits until it is revealed; one already showing slides on.
    if (fresh) hintCard.place(from)
    else hintCard.slideTo(to)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "movewindowv2") {
        var fields = String(event.data).split(",")
        root.lastMove = { address: fields[0], id: parseInt(fields[1], 10), time: Date.now() }
      } else if (name === "workspacev2") {
        root.showSwitch(parseInt(String(event.data).split(",")[0], 10))
      } else if (name === "changefloatingmode" || name === "pin") {
        var parts = String(event.data).split(",")
        root.noteLevelEvent(parts[0].replace(/^0x/, ""), name === "pin" ? "pinned" : "floating", parts[1] === "1")
      } else if (name === "closewindow") {
        delete root.levelState[String(event.data).replace(/^0x/, "")]
      }
    }
  }

  // Shown for the slide plus a short hold (set per switch), then a fade
  // before the window goes. Each switch starts the hold again.
  Timer {
    id: hintHold
    onTriggered: {
      root.hintShown = false
      hintUnmap.restart()
    }
  }

  Timer {
    id: hintUnmap
    interval: Style.duration(100)
    onTriggered: root.hintMapped = false
  }

  OverlayWindow {
    id: hintPanel
    shown: root.hintMapped
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "guykawaii-switch-hint"
    // Visual only: an empty input region never blocks clicks below it.
    mask: Region {}

    onContentRevealedChanged: if (contentRevealed) {
      if (root.hintLevel) hintCard.slideLevel(root.levelTo)
      else hintCard.slideTo(root.hintTo)
    }

    BorderSurface {
      id: hintCard

      // Cells, gaps and the grid's place in whole screen pixels (see root.px),
      // so every cell and gap comes out the same width at a fractional scale.
      readonly property real pad: root.px(Style.space(10))
      readonly property real cellGap: root.line(Style.space(4))
      readonly property real cellW: root.line(Style.space(22))
      readonly property real cellH: root.line(cellW * hintPanel.height / Math.max(1, hintPanel.width))
      readonly property real gridW: root.columns * cellW + (root.columns - 1) * cellGap
      readonly property real gridH: root.rows * cellH + (root.rows - 1) * cellGap
      // A carry's caption never widens the card; its name is cut to fit instead.
      readonly property real innerW: root.px(Math.max(gridW, hintLabel.implicitWidth))
      readonly property bool captioned: root.hintCarry || root.hintLevel
      readonly property real captionH: captioned ? cellGap * 2 + hintCaption.implicitHeight : 0
      // The plain switch card's height. A carry adds its caption below it, so the
      // label and grid sit in the same place either way.
      readonly property real plainH: borderTop + pad * 2 + borderBottom + hintLabel.implicitHeight + cellGap * 2 + gridH

      function cellX(slot) { return ((slot - 1) % root.columns) * (cellW + cellGap) }
      function cellY(slot) { return Math.floor((slot - 1) / root.columns) * (cellH + cellGap) }

      // The level cells: three across the grid's footprint, so the card keeps
      // its size and place whichever hint it shows.
      // Wide gaps: the direction marks sit in them, never over a picture.
      readonly property real levelGap: root.line(Style.space(14))
      readonly property real levelW: root.px((gridW - 2 * levelGap) / 3)
      function levelX(level) { return root.px((gridW - 3 * levelW - 2 * levelGap) / 2) + level * (levelW + levelGap) }

      function placeLevel(level) {
        levelSlide.stop()
        levelMarker.x = levelX(level)
      }

      function slideLevel(level) {
        levelSlide.stop()
        levelSlideX.to = levelX(level)
        levelSlide.start()
      }

      function place(slot) {
        slide.stop()
        highlight.x = cellX(slot)
        highlight.y = cellY(slot)
        hintArrow.grow = 0
      }

      // Slides the highlight on from wherever it is, and draws a carry's arrow
      // again from its new origin; a new switch restarts it, nothing queues.
      function slideTo(slot) {
        slide.stop()
        slideX.to = cellX(slot)
        slideY.to = cellY(slot)
        slide.start()
      }

      width: borderLeft + pad * 2 + borderRight + innerW
      height: plainH + captionH
      x: root.px((parent.width - width) / 2)
      // Pinned by the plain card's top, so a carry grows the card downwards.
      y: root.px(parent.height - Style.space(67) - plainH)
      color: Util.alpha(Commons.Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.hintShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic } }

      // "3 → 4", for a switch and a carry alike.
      Text {
        id: hintLabel
        x: hintCard.borderLeft + hintCard.pad + (hintCard.innerW - implicitWidth) / 2
        y: hintCard.borderTop + hintCard.pad
        textFormat: Text.PlainText
        text: root.hintText
        color: Commons.Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Item {
        id: hintGrid
        visible: !root.hintLevel
        x: root.px(hintCard.borderLeft + hintCard.pad + (hintCard.innerW - hintCard.gridW) / 2)
        y: root.px(hintLabel.y + hintLabel.implicitHeight + hintCard.cellGap * 2)

        // The same cells as the bar's grid: solid with windows, an outline when
        // empty. Bound to the live window lists, so the slot a carried window
        // left shows what is still there after the move.
        Repeater {
          model: root.slots
          delegate: SlotCell {
            required property int index
            readonly property var workspace: { root.hintMapped; return root.workspaceById(root.hintBlock * root.slots + index + 1) }
            occupied: !!workspace && workspace.toplevels.values.length > 0
            ink: Commons.Color.popups.text
            dpr: root.dpr
            // On a carry every cell steps back (the origin too: the arrow starts
            // on it), so the accent arrow keeps at least 3:1 against whatever is
            // under it, solid or empty (WCAG 1.4.11 for graphics).
            opacity: root.hintCarry ? 0.35 : 1
            x: hintCard.cellX(index + 1)
            y: hintCard.cellY(index + 1)
            width: hintCard.cellW
            height: hintCard.cellH
          }
        }

        // A carry's track: from the middle of the slot the window left towards
        // the slot it went to, stopping a little before that cell (the marker's
        // extra pixel and some air), so it never runs under the marker. One
        // colour (the theme's foreground unless set), over cells that step back.
        // Rotated, so any direction works; a wrap (5 → 1) is drawn the same way,
        // back across the row.
        component HintArrow: Item {
          id: arrow

          // Where it starts (its left middle), its direction in degrees and its
          // full length once grown.
          property real sx: 0
          property real sy: 0
          property real angle: 0
          property real fullLength: 0
          // 0 → 1 with the highlight's slide.
          property real grow: 0
          readonly property real length: root.px(Math.max(0, fullLength) * grow)
          // Sized in whole screen pixels, the shaft an even number of them, so
          // the head reaches as far above the shaft as below it at any scale.
          readonly property real headLength: root.line(Style.space(7))
          readonly property real headHalf: root.line(Style.space(5))
          readonly property real shaft: Math.max(2, 2 * Math.round(Style.space(3) * root.dpr / 2)) / root.dpr
          readonly property color ink: root.carryArrowColor
          property bool active: false

          visible: active && length >= headLength
          // Its left middle sits on the start, and it turns around it.
          x: root.px(sx)
          y: root.px(sy - headHalf)
          width: length
          height: headHalf * 2
          transformOrigin: Item.Left
          rotation: angle

          // Shaft.
          Rectangle {
            width: arrow.length - arrow.headLength + 1
            height: arrow.shaft
            radius: height / 2
            y: arrow.headHalf - arrow.shaft / 2
            color: arrow.ink
          }

          // Head: a small triangle at the tip.
          Shape {
            x: arrow.length - arrow.headLength
            width: arrow.headLength
            height: parent.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
              strokeColor: "transparent"
              fillColor: arrow.ink
              startX: 0; startY: 0
              PathLine { x: arrow.headLength; y: arrow.headHalf }
              PathLine { x: 0; y: arrow.height }
              PathLine { x: 0; y: 0 }
            }
          }
        }

        // The route: straight from the origin's centre to the target's edge.
        readonly property int arrowFrom: Math.max(1, root.hintFrom)
        readonly property int arrowTo: Math.max(1, root.hintTo)
        readonly property real dx: hintCard.cellX(arrowTo) - hintCard.cellX(arrowFrom)
        readonly property real dy: hintCard.cellY(arrowTo) - hintCard.cellY(arrowFrom)
        readonly property real distance: Math.sqrt(dx * dx + dy * dy)
        // From the target's centre to its edge along the line, plus the 3 px.
        readonly property real toEdge: Math.min(
          dx !== 0 ? (hintCard.cellW / 2 + Style.space(3)) * distance / Math.abs(dx) : Infinity,
          dy !== 0 ? (hintCard.cellH / 2 + Style.space(3)) * distance / Math.abs(dy) : Infinity)

        HintArrow {
          id: hintArrow
          active: root.hintCarry && root.hintFrom !== root.hintTo
          sx: hintCard.cellX(hintGrid.arrowFrom) + hintCard.cellW / 2
          sy: hintCard.cellY(hintGrid.arrowFrom) + hintCard.cellH / 2
          angle: Math.atan2(hintGrid.dy, hintGrid.dx) * 180 / Math.PI
          fullLength: hintGrid.distance - hintGrid.toEdge
        }

        // The current slot, marked as on the bar.
        SlotMarker {
          id: highlight
          width: hintCard.cellW
          height: hintCard.cellH
          ink: Commons.Color.popups.text
          accent: Commons.Color.accent
          dpr: root.dpr

          // Style.duration: with reduced motion all three jump to the end.
          ParallelAnimation {
            id: slide
            NumberAnimation { id: slideX; target: highlight; property: "x"; duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
            NumberAnimation { id: slideY; target: highlight; property: "y"; duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
            NumberAnimation { target: hintArrow; property: "grow"; from: 0; to: 1; duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }
        }
      }

      // The level hint: tiled, floating, popped from left to right (a spread
      // moves right), each cell a small picture of that level. The other cells
      // step back, and a triangle in each gap the change crossed points the way
      // it went (a SUPER jump crosses two).
      Item {
        id: levelGrid
        visible: root.hintLevel
        x: hintGrid.x
        y: hintGrid.y
        width: hintCard.gridW
        height: hintCard.gridH

        readonly property real stroke: root.line(2)

        // A cell's picture, in the cell's ink (background on the accent cell,
        // foreground on the others), all three on the same inner box:
        //   tiled     two panes side by side, the window's solid
        //   floating  one smaller window, alone in the middle
        //   popped    a bigger window with another stacked behind it (on every workspace)
        component LevelPicture: Item {
          id: pic
          property int level: 0
          property color ink: "white"
          readonly property real s: levelGrid.stroke
          readonly property real m: root.px(Math.max(3, height * 0.16))
          readonly property real bw: width - m * 2
          readonly property real bh: height - m * 2

          Rectangle {
            visible: pic.level === 0
            x: pic.m; y: pic.m
            width: root.px((pic.bw - pic.s) / 2); height: pic.bh
            color: pic.ink
          }
          Rectangle {
            visible: pic.level === 0
            x: pic.m + root.px((pic.bw + pic.s) / 2); y: pic.m
            width: pic.width - pic.m - x; height: pic.bh
            color: "transparent"; border.width: pic.s; border.color: pic.ink
          }
          Rectangle {
            visible: pic.level === 1
            width: root.px(pic.bw * 0.62); height: root.px(pic.bh * 0.62)
            x: root.px((pic.width - width) / 2); y: root.px((pic.height - height) / 2)
            color: pic.ink
          }
          Rectangle {
            visible: pic.level === 2
            width: root.px(pic.bw * 0.64); height: root.px(pic.bh * 0.64)
            x: pic.m + pic.bw - width; y: pic.m
            color: "transparent"; border.width: pic.s; border.color: pic.ink
          }
          Rectangle {
            visible: pic.level === 2
            width: root.px(pic.bw * 0.64); height: root.px(pic.bh * 0.64)
            x: pic.m; y: pic.m + pic.bh - height
            color: pic.ink
          }
        }

        Repeater {
          model: 3
          delegate: Rectangle {
            required property int index
            x: hintCard.levelX(index)
            width: hintCard.levelW
            height: hintCard.gridH
            radius: Math.min(2, Style.cornerRadius)
            color: "transparent"
            border.width: levelGrid.stroke
            border.color: Util.alpha(Commons.Color.popups.text, 0.5)
            opacity: index === root.levelTo ? 1 : 0.7
          }
        }

        // Direction: a solid triangle in each gap between the old level and the
        // new one, pointing the way the window went.
        Repeater {
          model: 2
          delegate: Shape {
            id: tri
            required property int index
            readonly property int lo: Math.min(root.levelFrom, root.levelTo)
            readonly property int hi: Math.max(root.levelFrom, root.levelTo)
            visible: index >= lo && index < hi
            width: root.line(Style.space(9))
            height: root.line(Style.space(13))
            x: hintCard.levelX(index) + hintCard.levelW + root.px((hintCard.levelGap - width) / 2)
            y: root.px((hintCard.gridH - height) / 2)
            rotation: root.levelTo < root.levelFrom ? 180 : 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeColor: "transparent"
              fillColor: root.carryArrowColor
              startX: 0; startY: 0
              PathLine { x: tri.width; y: tri.height / 2 }
              PathLine { x: 0; y: tri.height }
              PathLine { x: 0; y: 0 }
            }
          }
        }

        SlotMarker {
          id: levelMarker
          width: hintCard.levelW
          height: hintCard.gridH
          ink: Commons.Color.popups.text
          accent: Commons.Color.accent
          dpr: root.dpr

          ParallelAnimation {
            id: levelSlide
            NumberAnimation { id: levelSlideX; target: levelMarker; property: "x"; duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }
        }

        // Pictures over the cells and the marker.
        Repeater {
          model: 3
          delegate: LevelPicture {
            required property int index
            level: index
            x: hintCard.levelX(index)
            width: hintCard.levelW
            height: hintCard.gridH
            ink: index === root.levelTo ? Commons.Color.background : Commons.Color.popups.text
            opacity: index === root.levelTo ? 1 : 0.7
          }
        }
      }

      // A carry or a level change names the window: its app's icon (or first letter) and name.
      Row {
        id: hintCaption
        visible: hintCard.captioned
        x: hintCard.borderLeft + hintCard.pad + (hintCard.innerW - implicitWidth) / 2
        y: hintGrid.y + hintCard.gridH + hintCard.cellGap * 2
        spacing: Style.space(5)

        Item {
          width: Style.space(14)
          height: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter

          Image {
            id: hintAppIcon
            anchors.fill: parent
            source: hintCard.captioned ? root.hintIcon : ""
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: false
            visible: status === Image.Ready
          }

          Rectangle {
            visible: !hintAppIcon.visible
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius / 3)
            color: Commons.Color.accent
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.hintLetter
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.hintApp
          width: Math.min(implicitWidth, hintCard.innerW - Style.space(14) - hintCaption.spacing)
          elide: Text.ElideRight
          color: Commons.Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
