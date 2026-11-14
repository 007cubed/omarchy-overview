import QtQuick
import qs.Commons

// One workspace slot as the bar and the switch hint draw it: solid when the
// workspace has windows, only an outline when it is empty.
Rectangle {
  property bool occupied: false
  // Text colour of the surface it sits on.
  property color ink: "white"

  radius: Math.min(2, Style.cornerRadius)
  color: occupied ? Util.alpha(ink, 0.85) : "transparent"
  // At least a hairline: an empty cell is only its outline.
  border.width: occupied ? 0 : Math.max(1, Style.normalBorderWidth)
  border.color: Util.alpha(ink, 0.5)
}
