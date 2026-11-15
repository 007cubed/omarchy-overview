import QtQuick
import QtQuick.Shapes

// The shape of a workspace layout: a disc for scrolling, a flat-based triangle
// for floating (Omarchy's own shapes), nothing for tiling. The disc fills the
// item's height, centred; the triangle fills the whole item. LayoutMark sizes
// it for slot cells, the overview's badges size it beside their number.
Item {
  id: shape

  property string mode: "dwindle"
  property color ink: "white"

  visible: mode === "scrolling" || mode === "floating"

  Rectangle {
    visible: shape.mode === "scrolling"
    anchors.centerIn: parent
    width: shape.height
    height: shape.height
    radius: height / 2
    color: shape.ink
  }

  Loader {
    active: shape.mode === "floating"
    anchors.fill: parent
    sourceComponent: Shape {
      id: tri
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillColor: shape.ink
        startX: tri.width / 2; startY: 0
        PathLine { x: tri.width; y: tri.height }
        PathLine { x: 0; y: tri.height }
        PathLine { x: tri.width / 2; y: 0 }
      }
    }
  }
}
