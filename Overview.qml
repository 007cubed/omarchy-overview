import Quickshell
import Quickshell.Hyprland
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
//   drag a number badge swap the whole workspace with the one it is dropped on
// A drag picks the neighbouring workspace in the direction it moves, after a
// fifth of a tile on each axis; dropped back near its start, it cancels. While
// dragging, the start tile has a dashed outline, the target a solid one, and the line under the
// grid says what the drop will do.
//                       (Super + drag anywhere too, when Hyprland lets Super through)
//   1-9, 0              go to that slot;  Esc closes
// Outside the overview, a switch to another workspace flashes a small 5x2 card
// at the bottom of the screen with the highlight sliding from the old slot to
// the new one, so moving between rows reads as moving up or down.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
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
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
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

  function swapSlots(a, b) {
    var fromA = root.windowsIn(a)
    var fromB = root.windowsIn(b)
    for (var i = 0; i < fromA.length; i++) root.moveWindow(fromA[i], b)
    for (var j = 0; j < fromB.length; j++) root.moveWindow(fromB[j], a)
  }

  function focusSlot(slot) {
    if (/^[A-Za-z0-9._-]+$/.test(root.monitorName))
      Hyprland.dispatch('o.workspaces.focus(' + slot + ', "' + root.monitorName + '")')
    else
      Hyprland.dispatch('hl.dsp.focus({ workspace = "' + root.workspaceId(slot) + '" })')
  }

  function focusWindow(toplevel) {
    var address = root.addressOf(toplevel)
    if (!address) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  // Only events that move, add or remove windows change the previews; focus,
  // title and layout events would only cause needless refreshes.
  readonly property var refreshEvents: ({
    openwindow: true, closewindow: true, movewindow: true, movewindowv2: true,
    changefloatingmode: true, fullscreen: true, pin: true,
    workspace: true, workspacev2: true, createworkspace: true, createworkspacev2: true,
    destroyworkspace: true, destroyworkspacev2: true, moveworkspace: true, moveworkspacev2: true
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
    var badge = badges.itemAt(slot - 1)
    var b = stage.mapToItem(badge, p.x, p.y)
    var onBadge = b.x >= 0 && b.y >= 0 && b.x <= badge.width && b.y <= badge.height
    var wholeWorkspace = withSuper || onBadge
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
  function tileX(slot) { return stage.gridX + ((slot - 1) % root.columns) * (stage.tileW + root.gap) }
  function tileY(slot) { return stage.gridY + Math.floor((slot - 1) / root.columns) * (stage.tileH + root.gap) }

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
      readonly property real availH: height - root.gap * 6 - hint.height
      readonly property real aspect: root.monH / Math.max(1, root.monW)
      readonly property real tileW: Math.max(40, Math.min(
        (availW - root.gap * (root.columns - 1)) / root.columns,
        ((availH - root.gap * (root.rows - 1)) / root.rows) / aspect))
      readonly property real tileH: tileW * aspect
      readonly property real tileScale: tileW / Math.max(1, root.monW)
      readonly property real gridW: root.columns * tileW + (root.columns - 1) * root.gap
      readonly property real gridH: root.rows * tileH + (root.rows - 1) * root.gap
      readonly property real gridX: (width - gridW) / 2
      readonly property real gridY: (height - gridH) / 2 - hint.height / 2

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      // Tile backgrounds. Previews and badges are separate layers above them, so
      // there is one preview per window rather than one per window per tile.
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

          x: root.tileX(slot)
          y: root.tileY(slot)
          width: stage.tileW
          height: stage.tileH
          radius: root.radius
          color: target ? root.selectedBackground : (origin ? Qt.darker(root.background, 1.4) : root.background)
          border.width: active || target ? Math.max(2, Style.normalBorderWidth * 2) : Style.normalBorderWidth
          border.color: active || target ? root.accent : Commons.Color.menu.border
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
              width: parent.width - 6
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
        readonly property real lineWidth: Math.max(2, Style.normalBorderWidth * 2)
        visible: root.dragging && root.pressSlot > 0
        z: 2.5
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
        z: 2.5
        x: visible ? root.tileX(root.hoverSlot) : 0
        y: visible ? root.tileY(root.hoverSlot) : 0
        width: stage.tileW
        height: stage.tileH
        radius: root.radius
        color: "transparent"
        border.width: dragOrigin.lineWidth
        border.color: root.accent
      }

      // Slot numbers, bottom-left of each tile: the handle for dragging a workspace.
      Repeater {
        id: badges
        model: root.slots

        delegate: Rectangle {
          id: badge
          required property int index
          readonly property int slot: index + 1
          readonly property bool active: root.activeSlot() === slot

          z: 3
          x: root.tileX(slot) + Style.spacing.sm
          y: root.tileY(slot) + stage.tileH - height - Style.spacing.sm
          width: Math.max(height, label.implicitWidth + Style.spacing.md * 2)
          height: label.implicitHeight + Style.spacing.sm * 2
          radius: root.radius
          color: active ? root.accent : Qt.rgba(0, 0, 0, 0.45)

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

      Text {
        id: hint
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.gridY + stage.gridH + root.gap
        width: Math.min(implicitWidth, stage.width - root.gap * 2)
        elide: Text.ElideRight
        text: root.dragging ? root.dragText() : strings.t("hint")
        color: root.foreground
        opacity: root.dragging ? 1 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // All clicks and drags go through here, so a drag survives previews
      // being refreshed underneath it.
      MouseArea {
        anchors.fill: parent
        z: 50
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: function(mouse) {
          root.beginPress(Qt.point(mouse.x, mouse.y), root.superHeld || (mouse.modifiers & Qt.MetaModifier) !== 0)
        }
        onPositionChanged: function(mouse) { root.movePress(Qt.point(mouse.x, mouse.y)) }
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
        color: root.pressKind === "workspace" ? Qt.rgba(0, 0, 0, 0.25) : root.background
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
  property int lastWorkspaceId: -1
  // hintMapped keeps the window up while the card fades out after hintShown.
  property bool hintShown: false
  property bool hintMapped: false

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function showSwitch(id) {
    var previous = root.lastWorkspaceId
    root.lastWorkspaceId = id
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
    var fresh = !root.hintMapped

    root.hintBlock = block
    root.hintFrom = from
    root.hintTo = to
    root.hintMapped = true
    root.hintShown = true
    hintHold.restart()
    hintUnmap.stop()
    // A fresh card waits until it is revealed; one already showing slides on.
    if (fresh) hintCard.place(from)
    else hintCard.slideTo(to)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "workspacev2")
        root.showSwitch(parseInt(String(event.data).split(",")[0], 10))
    }
  }

  // Shown for the slide plus 700 ms, then a short fade before the window goes.
  Timer {
    id: hintHold
    interval: Style.duration(160) + 700
    onTriggered: {
      root.hintShown = false
      hintUnmap.restart()
    }
  }

  Timer {
    id: hintUnmap
    interval: Style.duration(120)
    onTriggered: root.hintMapped = false
  }

  OverlayWindow {
    id: hintPanel
    shown: root.hintMapped
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "guykawaii-switch-hint"
    // Visual only: an empty input region never blocks clicks below it.
    mask: Region {}

    onContentRevealedChanged: if (contentRevealed) hintCard.slideTo(root.hintTo)

    BorderSurface {
      id: hintCard

      readonly property int pad: Style.space(10)
      readonly property int cellGap: Style.space(4)
      readonly property int cellW: Style.space(22)
      readonly property int cellH: Math.round(cellW * hintPanel.height / Math.max(1, hintPanel.width))

      function cellX(slot) { return ((slot - 1) % root.columns) * (cellW + cellGap) }
      function cellY(slot) { return Math.floor((slot - 1) / root.columns) * (cellH + cellGap) }

      function place(slot) {
        slide.stop()
        highlight.x = cellX(slot)
        highlight.y = cellY(slot)
      }

      function slideTo(slot) {
        slide.stop()
        slideX.to = cellX(slot)
        slideY.to = cellY(slot)
        slide.start()
      }

      width: borderLeft + pad * 2 + borderRight + root.columns * cellW + (root.columns - 1) * cellGap
      height: borderTop + pad * 2 + borderBottom + root.rows * cellH + (root.rows - 1) * cellGap
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Commons.Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.hintShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Item {
        x: hintCard.borderLeft + hintCard.pad
        y: hintCard.borderTop + hintCard.pad

        // Workspaces with windows read solid, empty ones faint.
        Repeater {
          model: root.slots
          delegate: Rectangle {
            required property int index
            readonly property var workspace: { root.hintMapped; return root.workspaceById(root.hintBlock * root.slots + index + 1) }
            readonly property bool occupied: !!workspace && workspace.toplevels.values.length > 0
            x: hintCard.cellX(index + 1)
            y: hintCard.cellY(index + 1)
            width: hintCard.cellW
            height: hintCard.cellH
            radius: Math.max(2, Style.cornerRadius / 3)
            color: Util.alpha(Commons.Color.popups.text, occupied ? 0.8 : 0.3)
          }
        }

        // The current slot, in the accent colour over its cell.
        Rectangle {
          id: highlight
          width: hintCard.cellW
          height: hintCard.cellH
          radius: Math.max(2, Style.cornerRadius / 3)
          color: Commons.Color.accent

          ParallelAnimation {
            id: slide
            NumberAnimation { id: slideX; target: highlight; property: "x"; duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
            NumberAnimation { id: slideY; target: highlight; property: "y"; duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }
        }
      }
    }
  }
}
