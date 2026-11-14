import QtQuick
import qs.Commons

// One workspace slot as the bar and the switch hint draw it: solid when the
// workspace has windows, only an outline when it is empty. A scrolling or
// floating workspace carries its layout mark: cut out of a solid cell (in the
// colour of the surface under it), drawn in the outline's ink in an empty one.
Rectangle {
  id: cell
  property bool occupied: false
  // Text colour of the surface it sits on.
  property color ink: "white"
  // The opaque colour the cell sits on, for a mark cut out of a solid cell.
  property color surface: "black"
  // The workspace's layout: "dwindle", "scrolling" or "floating".
  property string mode: "dwindle"
  // The layout's colour for its mark (the theme's, from LayoutModes).
  property color markColor: ink
  // The screen's scale: the outline is a whole number of screen pixels.
  property real dpr: 1

  radius: Math.min(2, Style.cornerRadius)
  color: occupied ? Util.alpha(ink, 0.85) : "transparent"
  // At least a hairline: an empty cell is only its outline.
  border.width: occupied ? 0 : Math.max(1, Math.round(Style.normalBorderWidth * dpr)) / dpr
  border.color: Util.alpha(ink, 0.5)

  LayoutMark {
    mode: cell.mode
    ink: cell.markColor
    halo: cell.occupied ? cell.surface : "transparent"
    dpr: cell.dpr
    cellWPx: Math.round(cell.width * cell.dpr)
    cellHPx: Math.round(cell.height * cell.dpr)
    borderPx: Math.max(1, Math.round(Style.normalBorderWidth * cell.dpr))
  }
}
