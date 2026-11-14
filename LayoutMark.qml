import QtQuick
import QtQuick.Shapes

// A workspace's layout as a small mark in a slot cell (bar and hint card):
// a disc for scrolling, a flat-based triangle for floating (Omarchy's own
// shapes for them), nothing for tiling. Smooth shapes in a box of whole screen
// pixels in the cell's right part, the same place in every cell. Give it the
// cell's size in screen pixels; it places itself.
Item {
  id: mark

  property string mode: "dwindle"
  property color ink: "white"
  property real dpr: 1
  property int cellWPx: 0
  property int cellHPx: 0
  // The cell's outline, in screen pixels: the mark keeps a pixel clear of it.
  property int borderPx: 1

  // Height: half the cell, even, a pixel clear of the outline, at most 10 (6
  // in the bar and 10 in the hint card at 1.6). Under 4 there is no room.
  readonly property int fit: Math.min(Math.floor(cellHPx / 2), cellHPx - 2 * borderPx - 2)
  readonly property int s: Math.min(10, fit - fit % 2)
  readonly property int w: s + 2
  readonly property int inset: Math.floor((cellHPx - s) / 2)

  visible: (mode === "scrolling" || mode === "floating") && s >= 4
  x: (cellWPx - inset - w) / dpr
  y: inset / dpr
  width: w / dpr
  height: s / dpr

  Rectangle {
    visible: mark.mode === "scrolling"
    x: 1 / mark.dpr
    width: mark.s / mark.dpr
    height: width
    radius: width / 2
    color: mark.ink
  }

  Loader {
    active: mark.mode === "floating"
    anchors.fill: parent
    sourceComponent: Shape {
      id: tri
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillColor: mark.ink
        startX: tri.width / 2; startY: 0
        PathLine { x: tri.width; y: tri.height }
        PathLine { x: 0; y: tri.height }
        PathLine { x: tri.width / 2; y: 0 }
      }
    }
  }
}
