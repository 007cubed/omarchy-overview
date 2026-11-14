import QtQuick
import qs.Commons

// The current slot, placed exactly over its SlotCell: an accent cell with a ring
// in the surface's text colour, a pixel larger than the cell, so it reads
// without colour too. Position it like a cell; it draws the extra pixel itself.
Item {
  property color ink: "white"
  property color accent: "steelblue"
  // The screen's scale: the ring is a whole number of screen pixels.
  property real dpr: 1
  readonly property real ring: Math.max(1, Math.round(Style.normalBorderWidth * dpr)) / dpr

  Rectangle {
    anchors.fill: parent
    anchors.margins: -ring
    radius: Math.min(3, Style.cornerRadius + 1)
    color: parent.accent
    border.width: ring
    border.color: parent.ink
  }
}
