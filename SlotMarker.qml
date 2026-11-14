import QtQuick
import qs.Commons

// The current slot, placed exactly over its SlotCell: an accent cell with a ring
// in the surface's text colour, a pixel larger than the cell, so it reads
// without colour too. Position it like a cell; it draws the extra pixel itself.
Item {
  property color ink: "white"
  property color accent: "steelblue"

  Rectangle {
    anchors.fill: parent
    anchors.margins: -1
    radius: Math.min(3, Style.cornerRadius + 1)
    color: parent.accent
    border.width: 1
    border.color: parent.ink
  }
}
