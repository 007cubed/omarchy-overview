#!/bin/bash
# Turn a recording into a README GIF: trim, crop, scale, burn in chips, palette.
# Usage: demo/render.sh NAME START DURATION CROP WIDTH [FPS]
#   CROP is w:h:x:y in physical pixels, "full" for the whole screen.
#   Chips come from NAME.cues (written by takes.sh), shown for 0.8 s each,
#   at the bottom, or at CHIP_Y (an ffmpeg expression, e.g. CHIP_Y=24 for the top).
# Example: demo/render.sh switch-hint 1.0 5.0 640:400:960:1180 640 25
set -euo pipefail
source "$(dirname "$0")/env.sh"

name=$1 start=$2 duration=$3 crop=$4 width=$5 fps=${6:-20}
font=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
src=$OUT_DIR/$name.mp4 out=$OUT_DIR/$name.gif

filters=""
[[ $crop != full ]] && filters="crop=$crop,"
filters+="fps=$fps,scale=$width:-1:flags=lanczos"

# One drawtext per chip; times are shifted by the trim start.
if [[ -f $OUT_DIR/$name.cues ]]; then
  i=0
  while IFS=$'\t' read -r t text; do
    i=$((i + 1))
    printf '%s' "$text" >"$STATE/chip$i.txt"
    from=$(awk -v a="$t" -v b="$start" 'BEGIN { printf "%.2f", a - b }')
    filters+=",drawtext=fontfile=$font:textfile=$STATE/chip$i.txt:fontsize=$((width / 30)):fontcolor=white"
    filters+=":box=1:boxcolor=0x1a1b26@0.9:boxborderw=12:x=(w-text_w)/2:y=${CHIP_Y:-h-text_h-24}"
    filters+=":enable='between(t,$from,$from+0.8)'"
  done <"$OUT_DIR/$name.cues"
fi

ffmpeg -v error -y -ss "$start" -t "$duration" -i "$src" -filter_complex \
  "[0:v]$filters,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$out"
echo "$out $(du -h "$out" | cut -f1)"
