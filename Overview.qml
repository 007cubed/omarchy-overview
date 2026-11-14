import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Workspace overview for the focused monitor: its ten Omarchy workspace slots
// in a 5x2 grid with live window previews.
//   click a window      focus it and close
//   click a workspace   go there and close
//   drag a window       move it to the workspace it is dropped on
//   drag a number badge swap the whole workspace with the one it is dropped on
//                       (Super + drag anywhere too, when Hyprland lets Super through)
//   1-9, 0              go to that slot;  Esc closes
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

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

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.opened) refreshTimer.restart()
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
    var tile = tiles.itemAt(slot - 1)
    if (!tile) return null
    var best = null
    for (var i = 0; i < tile.windowItems.count; i++) {
      var w = tile.windowItems.itemAt(i)
      if (!w || !w.visible) continue
      var q = stage.mapToItem(w, p.x, p.y)
      if (q.x < 0 || q.y < 0 || q.x > w.width || q.y > w.height) continue
      if (!best || w.z >= best.z) best = w
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
    var b = stage.mapToItem(tile.badgeItem, p.x, p.y)
    var onBadge = b.x >= 0 && b.y >= 0 && b.x <= tile.badgeItem.width && b.y <= tile.badgeItem.height
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
    if (root.dragging) root.hoverSlot = root.slotAt(p)
  }

  function endPress(p) {
    var kind = root.pressKind
    var from = root.pressSlot
    var toplevel = root.pressToplevel
    var wasDrag = root.dragging
    var target = wasDrag ? root.slotAt(p) : -1
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

  function slotAt(p) {
    for (var i = 0; i < tiles.count; i++) {
      var tile = tiles.itemAt(i)
      if (!tile) continue
      var q = stage.mapToItem(tile, p.x, p.y)
      if (q.x >= 0 && q.y >= 0 && q.x <= tile.width && q.y <= tile.height) return i + 1
    }
    return -1
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

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Grid {
        id: grid
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -hint.height / 2
        columns: root.columns
        spacing: root.gap

        Repeater {
          id: tiles
          model: root.slots

          delegate: Rectangle {
            id: tile
            required property int index
            readonly property int slot: index + 1
            readonly property bool active: root.activeSlot() === slot
            readonly property bool target: root.dragging && root.hoverSlot === slot && root.pressSlot !== slot
            readonly property bool lifted: root.dragging && root.pressKind === "workspace" && root.pressSlot === slot
            property alias windowItems: windowRepeater
            property alias badgeItem: badge

            width: stage.tileW
            height: stage.tileH
            radius: root.radius
            clip: true
            color: target ? root.selectedBackground : root.background
            border.width: active || target ? Math.max(2, Style.normalBorderWidth * 2) : Style.normalBorderWidth
            border.color: active || target ? root.accent : Commons.Color.menu.border
            opacity: lifted ? 0.4 : 1

            // One delegate per Hyprland window, shown on the tile it lives on.
            // Bound to the live window list rather than a filtered array, so
            // title changes don't rebuild delegates (and cancel a drag).
            Repeater {
              id: windowRepeater
              model: Hyprland.toplevels

              delegate: Rectangle {
                id: win
                required property var modelData
                readonly property var ipc: { root.revision; return modelData.lastIpcObject || {} }
                readonly property bool lifted: root.dragging && root.pressKind === "window" && root.pressToplevel === modelData
                readonly property bool here: !!modelData.workspace && modelData.workspace.id === root.workspaceId(tile.slot)
                  && !!ipc.at && !!ipc.size && !ipc.hidden

                visible: here
                z: ipc.floating ? 1 : 0

                x: ((ipc.at ? ipc.at[0] : 0) - root.monX) * stage.tileScale
                y: ((ipc.at ? ipc.at[1] : 0) - root.monY) * stage.tileScale
                width: Math.max(8, (ipc.size ? ipc.size[0] : 0) * stage.tileScale)
                height: Math.max(8, (ipc.size ? ipc.size[1] : 0) * stage.tileScale)
                radius: Math.max(2, root.radius / 2)
                color: Qt.darker(root.background, 1.25)
                border.width: 1
                border.color: Commons.Color.menu.border
                clip: true
                opacity: lifted ? 0.3 : 1

                ScreencopyView {
                  anchors.fill: parent
                  anchors.margins: 1
                  captureSource: root.opened && win.here ? win.modelData.wayland : null
                  live: root.opened
                }

                Text {
                  textFormat: Text.PlainText
                  visible: !win.modelData.wayland
                  anchors.centerIn: parent
                  width: parent.width - 6
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: String(win.ipc["class"] || win.modelData.title || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

              }
            }

            // Slot number, bottom-left; the handle for dragging the whole workspace.
            Rectangle {
              id: badge
              z: 2
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.spacing.sm
              width: Math.max(height, label.implicitWidth + Style.spacing.md * 2)
              height: label.implicitHeight + Style.spacing.sm * 2
              radius: root.radius
              color: tile.active ? root.accent : Qt.rgba(0, 0, 0, 0.45)

              Text {
                id: label
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: String(tile.slot % 10)
                color: tile.active ? root.background : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }
          }
        }
      }

      Text {
        id: hint
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: grid.bottom
        anchors.topMargin: root.gap
        width: Math.min(implicitWidth, stage.width - root.gap * 2)
        elide: Text.ElideRight
        text: strings.t("hint")
        color: root.foreground
        opacity: 0.7
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
}
