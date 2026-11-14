import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar workspaces in the overview's 5x2 shape: slots 1-5 are the top row and
// 6-10 the bottom one, so a row toggle (4 fingers down) shows as a move up or
// down. Two looks, picked by the "style" setting on the bar layout entry:
//   "grid"  a small 5x2 block of cells; the accent cell slides to the slot
//   "row"   the current row's five numbers, sliding up or down to the other
//           row, and a ▴/▾ that toggles row (accent when the other row has windows)
//   "combo" the current row's numbers, and the other row as five short bars on
//           the side it lies (below for 6-0, above for 1-5), solid where it has
//           windows; on a row change the numbers slide and the bars flip sides
// Click a slot to go there; the wheel steps through the slots. After the slots,
// the shown workspace's layout as Omarchy's widget draws it (a square tiles, a
// circle scrolls, a triangle floats); clicking it cycles to the next, as Super + L.
// Ported down from Omarchy's own Workspaces.qml (monitor blocks, click, wheel).
BarWidget {
  id: root
  moduleName: "guykawaii.overview"

  readonly property string style: root.setting("style", "grid")
  readonly property int slots: 10
  readonly property int columns: 5

  readonly property color foreground: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  // ---- monitor and slots (as in Omarchy's Workspaces.qml) ---------------------

  // Every monitor has slots 1-10 of its own, which Hyprland numbers in a block
  // of ten per monitor: 1-10, 11-20, and so on. Each bar shows its own block.
  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  readonly property int activeId: root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    return root.activeId > 0 ? Math.floor((root.activeId - 1) / root.slots) : 0
  }

  // The slot (1-10) the monitor shows, or -1 when it shows another block's.
  readonly property int activeSlot: root.activeId > 0 && Math.floor((root.activeId - 1) / root.slots) === root.block
    ? (root.activeId - 1) % root.slots + 1 : -1
  // 0 for the top row, 1 for the bottom one.
  readonly property int row: root.activeSlot > root.columns ? 1 : 0

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function occupied(slot) {
    var workspace = root.workspaceById(root.block * root.slots + slot)
    return workspace !== null && workspace.toplevels.values.length > 0
  }

  function focusSlot(slot) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote("o.workspaces.focus(" + slot + ", \"" + root.monitorName + "\")"))
  }

  function toggleRow() {
    var slot = root.activeSlot > 0 ? root.activeSlot : 1
    root.focusSlot(slot <= root.columns ? slot + root.columns : slot - root.columns)
  }

  // A wheel notch moves one slot, and a touchpad adds up its smaller deltas
  // until they make a notch's worth. It holds at either end.
  property real wheelAccumulator: 0

  function scrollSlots(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0 || root.activeSlot < 1) return
    var target = Util.clamp(root.activeSlot - wheel.steps, 1, root.slots)
    if (target !== root.activeSlot) root.focusSlot(target)
  }

  // Quickshell credits every workspace switch to the focused monitor and misses
  // some changes, so ask Hyprland for the truth after them (as the stock widget does).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  // Quickshell's first idea of the active workspace can be stale after a restart.
  Component.onCompleted: {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    root.refresh()
  }

  // ---- layout of the shown workspace (as in Omarchy's Workspaces.qml) ---------

  // Every workspace's layout, for the marks in the cells and the button.
  LayoutModes { id: layouts }
  readonly property string activeMode: layouts.mode(root.activeId)

  // Omarchy's glyphs for the layouts: a square tiles, a circle scrolls, a triangle floats.
  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  function opaque(c) { return Qt.rgba(c.r, c.g, c.b, 1) }

  function modeOf(slot) { return layouts.mode(root.block * root.slots + slot) }

  function refresh() { layouts.reload() }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  readonly property var modeOrder: ["dwindle", "scrolling", "floating"]
  function nextMode(mode) { return root.modeOrder[(root.modeOrder.indexOf(mode) + 1) % 3] }

  // The layout command acts on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused)
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    root.bar.run(command)
  }

  // This widget stands in for Omarchy's workspaces widget, so it answers the
  // refresh Omarchy's layout commands send it (Super + L, a new default).
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: Style.spaceReal(1.5)

  implicitWidth: look.implicitWidth + layoutButton.width + trailingGap
  implicitHeight: root.barSize

  Loader {
    id: look
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: root.style === "row" ? rowLook : (root.style === "combo" ? comboLook : gridLook)
  }

  WidgetButton {
    id: layoutButton
    anchors.left: look.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.activeId > 0
    bar: root.bar
    text: root.modeGlyph(root.activeMode)
    foreground: layouts.color(root.activeMode, root.foreground)
    tooltipText: strings.t("layout.tip").arg(strings.t("layout." + root.activeMode)).arg(strings.t("layout." + root.nextMode(root.activeMode)))
    horizontalMargin: 6
    verticalPadding: 6
    fixedWidth: Style.space(20)
    fixedHeight: root.barSize
    onPressed: root.cycleLayout()
    onWheelMoved: function(delta) { root.scrollSlots(delta) }
  }

  // ---- "grid": a 5x2 block of cells -------------------------------------------

  Component {
    id: gridLook

    Item {
      id: grid
      // Sized in whole screen pixels (at 1.6 a point is 1.6 pixels), so every
      // cell, gap and outline comes out the same width; worked out in pixels,
      // then turned back into points.
      readonly property real dpr: root.monitor && root.monitor.scale > 0 ? root.monitor.scale : 1
      readonly property int gapPx: Math.max(1, Math.round(Style.space(2) * dpr))
      readonly property int cellHPx: Math.max(4, Math.floor((root.barSize * dpr - Style.space(8) * dpr - gapPx) / 2))
      readonly property int cellWPx: Math.round(cellHPx * 1.6)
      readonly property int padPx: Math.round(Style.space(4) * dpr)
      readonly property int topPx: Math.floor((root.barSize * dpr - 2 * cellHPx - gapPx) / 2)
      readonly property real gap: gapPx / dpr
      readonly property real cellH: cellHPx / dpr
      readonly property real cellW: cellWPx / dpr
      readonly property real pad: padPx / dpr

      function cellX(slot) { return (padPx + ((slot - 1) % root.columns) * (cellWPx + gapPx)) / dpr }
      function cellY(slot) { return (topPx + Math.floor((slot - 1) / root.columns) * (cellHPx + gapPx)) / dpr }

      implicitWidth: pad * 2 + root.columns * cellW + (root.columns - 1) * gap
      implicitHeight: root.barSize

      // Occupied cells are solid, empty ones only an outline.
      Repeater {
        model: root.slots
        delegate: SlotCell {
          required property int index
          occupied: root.occupied(index + 1)
          mode: root.modeOf(index + 1)
          markColor: layouts.color(mode, root.foreground)
          ink: root.foreground
          surface: root.opaque(root.bar ? root.bar.background : Commons.Color.background)
          dpr: grid.dpr
          x: grid.cellX(index + 1)
          y: grid.cellY(index + 1)
          width: grid.cellW
          height: grid.cellH
        }
      }

      // The slot the monitor shows. One element, so it slides between cells and rows.
      SlotMarker {
        visible: root.activeSlot > 0
        mode: root.modeOf(Math.max(1, root.activeSlot))
        surface: root.opaque(root.bar ? root.bar.background : Commons.Color.background)
        ink: root.foreground
        accent: root.accent
        dpr: grid.dpr
        x: grid.cellX(Math.max(1, root.activeSlot))
        y: grid.cellY(Math.max(1, root.activeSlot))
        width: grid.cellW
        height: grid.cellH
        Behavior on x { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
        Behavior on y { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
      }

      // One hit area per slot, together covering the whole widget: its column
      // (gaps and the outer padding included) and its half of the bar height.
      // Hovering shows the slot number in the bar's tooltip.
      Repeater {
        model: root.slots
        delegate: MouseArea {
          id: hit
          required property int index
          readonly property int slot: index + 1
          readonly property int column: index % root.columns
          // The bar's tooltip asks its target whether it is still hovered.
          readonly property bool tooltipHovered: containsMouse

          x: column === 0 ? 0 : grid.cellX(slot) - grid.gap / 2
          width: (column === root.columns - 1 ? grid.width : grid.cellX(slot) + grid.cellW + grid.gap / 2) - x
          y: index < root.columns ? 0 : root.barSize / 2
          height: root.barSize / 2
          hoverEnabled: true
          onClicked: root.focusSlot(slot)
          onWheel: function(wheel) { root.scrollSlots(wheel.angleDelta.y) }
          onContainsMouseChanged: {
            if (!root.bar) return
            if (containsMouse) root.bar.showTooltip(hit, String(slot % 10))
            else root.bar.hideTooltip(hit)
          }
        }
      }
    }
  }

  // ---- "row": the current row's numbers ----------------------------------------

  Component {
    id: rowLook

    Row {
      readonly property real buttonWidth: Style.space(20)

      // Both rows stacked, one bar-height each; the window shows the current one.
      Item {
        width: root.columns * parent.buttonWidth
        height: root.barSize
        clip: true

        Column {
          id: rowStack
          y: -root.row * root.barSize
          Behavior on y { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

          Repeater {
            model: 2
            delegate: Row {
              required property int index
              readonly property int rowIndex: index

              Repeater {
                model: root.columns
                delegate: WidgetButton {
                  required property int index
                  readonly property int slot: rowIndex * root.columns + index + 1
                  readonly property bool shown: root.activeSlot === slot

                  bar: root.bar
                  text: String(slot % 10)
                  foreground: shown ? root.accent : root.foreground
                  opacity: shown || root.occupied(slot) ? 1 : 0.5
                  horizontalMargin: 6
                  verticalPadding: 6
                  fixedWidth: Style.space(20)
                  fixedHeight: root.barSize
                  onPressed: root.focusSlot(slot)
                  onWheelMoved: function(delta) { root.scrollSlots(delta) }
                }
              }
            }
          }
        }
      }

      // Points at the hidden row; accent when it has windows. Click toggles row.
      WidgetButton {
        readonly property int otherRow: 1 - root.row
        readonly property bool otherOccupied: {
          for (var i = 1; i <= root.columns; i++)
            if (root.occupied(otherRow * root.columns + i)) return true
          return false
        }

        bar: root.bar
        text: root.row === 0 ? "▾" : "▴"
        foreground: otherOccupied ? root.accent : root.foreground
        opacity: otherOccupied ? 1 : 0.5
        horizontalMargin: 4
        verticalPadding: 6
        fixedWidth: Style.space(14)
        fixedHeight: root.barSize
        onPressed: root.toggleRow()
        onWheelMoved: function(delta) { root.scrollSlots(delta) }
      }
    }
  }

  // ---- "combo": the current row's numbers over (or under) the other row ---------

  Component {
    id: comboLook

    Item {
      id: combo
      readonly property real buttonWidth: Style.space(20)
      readonly property int otherRow: 1 - root.row
      // The numbers move a little away from the bars to make room for them.
      readonly property real nudge: Style.space(3)
      readonly property real markHeight: Math.max(2, Style.space(2))
      readonly property real markMargin: Style.space(3)

      implicitWidth: root.columns * buttonWidth
      implicitHeight: root.barSize
      clip: true

      // Both rows of numbers stacked, one bar-height each, as in "row".
      Column {
        y: -root.row * root.barSize + (root.row === 0 ? -combo.nudge : combo.nudge)
        Behavior on y { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

        Repeater {
          model: 2
          delegate: Row {
            required property int index
            readonly property int rowIndex: index

            Repeater {
              model: root.columns
              delegate: WidgetButton {
                required property int index
                readonly property int slot: rowIndex * root.columns + index + 1
                readonly property bool shown: root.activeSlot === slot

                bar: root.bar
                text: String(slot % 10)
                foreground: shown ? root.accent : root.foreground
                opacity: shown || root.occupied(slot) ? 1 : 0.5
                horizontalMargin: 6
                verticalPadding: 6
                fixedWidth: combo.buttonWidth
                fixedHeight: root.barSize
                onPressed: root.focusSlot(slot)
                onWheelMoved: function(delta) { root.scrollSlots(delta) }
              }
            }
          }
        }
      }

      // The other row: a short bar under (or over) each column, solid where that
      // slot has windows. Click one to go there.
      Repeater {
        model: root.columns
        delegate: Rectangle {
          required property int index
          readonly property int slot: combo.otherRow * root.columns + index + 1

          x: index * combo.buttonWidth + combo.buttonWidth * 0.2
          y: combo.otherRow === 1 ? root.barSize - combo.markMargin - height : combo.markMargin
          width: combo.buttonWidth * 0.6
          height: combo.markHeight
          radius: height / 2
          color: Util.alpha(root.foreground, root.occupied(slot) ? 0.85 : 0.25)
          Behavior on y { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -combo.markMargin
            onClicked: root.focusSlot(parent.slot)
          }
        }
      }
    }
  }
}
