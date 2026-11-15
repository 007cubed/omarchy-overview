import QtQuick

// A workspace's layout as a mark centred in a slot cell (bar and hint card):
// LayoutShape sized to the cell in whole screen pixels. It fills the cell
// inside the outline (bar 10 px, hint card 21 px at 1.6), with the same parity
// as the cell so it sits exactly in the middle; the triangle is as tall as
// the disc and a little wider (1.15), so neither looks bigger. Give it the
// cell's size in screen pixels; it places itself.
LayoutShape {
  id: mark

  property real dpr: 1
  property int cellWPx: 0
  property int cellHPx: 0
  // The cell's outline, in screen pixels: the mark fills the cell inside it.
  property int borderPx: 1

  readonly property int fit: Math.min(cellHPx - 2 * borderPx,
                                      Math.floor((cellWPx - 2 * borderPx) / 1.15))
  readonly property int s: fit % 2 === cellHPx % 2 ? fit : fit - 1
  // The triangle's width takes the cell width's parity, so it centres exactly;
  // a disc can't match both, so an odd leftover goes to the right.
  readonly property int t: Math.round(s * 1.15)
  readonly property int w: mode === "floating" ? t + (cellWPx - t) % 2 : s

  visible: (mode === "scrolling" || mode === "floating") && s >= 4
  x: Math.floor((cellWPx - w) / 2) / dpr
  y: (cellHPx - s) / 2 / dpr
  width: w / dpr
  height: s / dpr
}
