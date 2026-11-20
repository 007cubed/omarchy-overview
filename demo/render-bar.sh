#!/bin/bash
# Stack the three bar takes (bar-grid, bar-row, bar-combo) into one GIF, each
# strip labelled with its style, scaled 2x with nearest neighbour so the 10 px
# cells stay sharp.
# Usage: demo/render-bar.sh [START] [DURATION]
set -euo pipefail
source "$(dirname "$0")/env.sh"

start=${1:-1.0} duration=${2:-7.4}
crop=230:42:52:0   # the widget on the left of the bar, after Omarchy's menu button
font=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
inputs=() filters="" labels=""

for i in 0 1 2; do
  style=(grid row combo); style=${style[$i]}
  inputs+=(-ss "$start" -t "$duration" -i "$OUT_DIR/bar-$style.mp4")
  filters+="[$i:v]crop=$crop,fps=20,scale=iw*2:ih*2:flags=neighbor,pad=iw+160:ih:160:0:color=0x1a1b26,"
  filters+="drawtext=fontfile=$font:text=$style:fontsize=26:fontcolor=0x9aa5ce:x=24:y=(h-text_h)/2[s$i];"
  labels+="[s$i]"
done

ffmpeg -v error -y "${inputs[@]}" -filter_complex \
  "${filters}${labels}vstack=3,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" \
  -loop 0 "$OUT_DIR/bar.gif"
echo "$OUT_DIR/bar.gif $(du -h "$OUT_DIR/bar.gif" | cut -f1)"
