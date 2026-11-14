import QtQuick
import qs.Commons

// The current slot, placed exactly over its SlotCell: an accent cell with a ring
// in the surface's text colour, a pixel larger than the cell, so it reads
// without colour too. Position it like a cell; it draws the extra pixel itself.
// It carries the slot's layout mark, cut out of the accent in whichever of the
// surface's text or background colour stands out more against it.
Item {
  id: marker
  property color ink: "white"
  property color accent: "steelblue"
  property color surface: "black"
  property string mode: "dwindle"
  // The screen's scale: the ring is a whole number of screen pixels.
  property real dpr: 1
  readonly property real ring: Math.max(1, Math.round(Style.normalBorderWidth * dpr)) / dpr

  // WCAG contrast between two colours.
  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  readonly property color markInk: contrast(accent, surface) >= contrast(accent, ink) ? surface : ink

  Rectangle {
    anchors.fill: parent
    anchors.margins: -ring
    radius: Math.min(3, Style.cornerRadius + 1)
    color: parent.accent
    border.width: ring
    border.color: parent.ink
  }

  LayoutMark {
    mode: marker.mode
    ink: marker.markInk
    dpr: marker.dpr
    cellWPx: Math.round(marker.width * marker.dpr)
    cellHPx: Math.round(marker.height * marker.dpr)
    borderPx: Math.max(1, Math.round(Style.normalBorderWidth * marker.dpr))
  }
}
