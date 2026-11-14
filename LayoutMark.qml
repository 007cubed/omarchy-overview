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
  // A one-pixel ring of this colour round the shape (a coloured mark on a solid
  // cell); transparent for none.
  property color halo: "transparent"
  property real dpr: 1
  property int cellWPx: 0
  property int cellHPx: 0
  // The cell's outline, in screen pixels: the mark keeps a pixel clear of it.
  property int borderPx: 1

  // Height: half the cell, even, a pixel clear of the outline, 4 to 10 (6 in
  // the bar and 10 in the hint card at 1.6). The triangle's base is two wider.
  readonly property int s: {
    var fit = Math.min(Math.floor(cellHPx / 2), cellHPx - 2 * borderPx - 2)
    return Math.max(4, Math.min(10, fit - fit % 2))
  }
  readonly property int w: s + 2
  readonly property int inset: Math.floor((cellHPx - s) / 2)

  visible: mode === "scrolling" || mode === "floating"
  x: (cellWPx - inset - w) / dpr
  y: inset / dpr
  width: w / dpr
  height: s / dpr

  // The ring first, a pixel bigger all round, then the shape.
  component Glyph: Item {
    id: glyph
    property color fill
    Rectangle {
      visible: mark.mode === "scrolling"
      x: (glyph.width - width) / 2
      y: (glyph.height - height) / 2
      width: glyph.height
      height: glyph.height
      radius: width / 2
      color: glyph.fill
    }
    Shape {
      id: tri
      visible: mark.mode === "floating"
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillColor: glyph.fill
        startX: tri.width / 2; startY: 0
        PathLine { x: tri.width; y: tri.height }
        PathLine { x: 0; y: tri.height }
        PathLine { x: tri.width / 2; y: 0 }
      }
    }
  }

  Glyph {
    visible: mark.halo.a > 0
    fill: mark.halo
    x: -1 / mark.dpr
    y: -1 / mark.dpr
    width: (mark.w + 2) / mark.dpr
    height: (mark.s + 2) / mark.dpr
  }
  Glyph {
    fill: mark.ink
    anchors.fill: parent
  }
}
