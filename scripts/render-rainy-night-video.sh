#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/ios/SulavSleep/Images.xcassets"
OUT_DIR="$ROOT_DIR/ios/SulavSleep/Video"
OUT_FILE="$OUT_DIR/RainyNightLoop.mp4"

WIDTH="${VIDEO_WIDTH:-720}"
HEIGHT="${VIDEO_HEIGHT:-1560}"
FPS="${VIDEO_FPS:-24}"
DURATION="${VIDEO_DURATION:-10}"
FRAME_COUNT=$((FPS * DURATION))

mkdir -p "$OUT_DIR"

ffmpeg -y -hide_banner \
  -loop 1 -framerate "$FPS" -t "$DURATION" \
  -i "$ASSET_DIR/NightCity.imageset/night-city.png" \
  -filter_complex "\
[0:v]scale=-2:${HEIGHT}:flags=neighbor,crop=${WIDTH}:${HEIGHT}:(iw-${WIDTH})/2:0,eq=saturation=0.58:brightness=-0.08:contrast=1.05,format=rgba[city];\
color=c=0xF4A261@0.16:s=${WIDTH}x${HEIGHT}:r=${FPS}:d=${DURATION},format=rgba[warm];\
[city][warm]overlay=0:0:format=auto[toned];\
color=c=0x00000000:s=${WIDTH}x${HEIGHT}:r=${FPS}:d=${DURATION},format=rgba,\
geq=r='244':g='162':b='97':\
a='min(48,(34*exp(-((X-W*0.22)*(X-W*0.22)/(2*170*170)+(Y-H*0.77)*(Y-H*0.77)/(2*95*95)))+38*exp(-((X-W*0.52)*(X-W*0.52)/(2*230*230)+(Y-H*0.80)*(Y-H*0.80)/(2*120*120)))+30*exp(-((X-W*0.84)*(X-W*0.84)/(2*185*185)+(Y-H*0.76)*(Y-H*0.76)/(2*100*100))))*(0.90+0.10*sin(2*PI*N/${FRAME_COUNT})))'[glow];\
[toned][glow]overlay=0:0:format=auto[glowing];\
color=c=0x00000000:s=${WIDTH}x${HEIGHT}:r=${FPS}:d=${DURATION},format=rgba,\
geq=r='190':g='208':b='224':\
a='if(lt(mod(X+0.28*Y+240*N/${FRAME_COUNT},240),1.8)*lt(mod(Y+320*N/${FRAME_COUNT},160),58),42,0)'[rain_far];\
[glowing][rain_far]overlay=0:0:format=auto[rain_a];\
color=c=0x00000000:s=${WIDTH}x${HEIGHT}:r=${FPS}:d=${DURATION},format=rgba,\
geq=r='205':g='220':b='232':\
a='if(lt(mod(X+0.36*Y+360*N/${FRAME_COUNT},360),2.4)*lt(mod(Y+520*N/${FRAME_COUNT},230),74),62,0)'[rain_near];\
[rain_a][rain_near]overlay=0:0:format=auto[rained];\
color=c=0x08111E@0.54:s=${WIDTH}x${HEIGHT}:r=${FPS}:d=${DURATION},format=rgba[scrim];\
[rained][scrim]overlay=0:0:format=auto,format=yuv420p[v]" \
  -map "[v]" \
  -an \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -b:v 950k \
  -allow_sw 1 \
  -movflags +faststart \
  "$OUT_FILE"

echo "Rendered $OUT_FILE"
