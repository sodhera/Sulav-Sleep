#!/usr/bin/env bash
set -euo pipefail

# Edit a full-screen simulator capture made with -capture-blocking-demo.
# Choose a capture whose home screen begins at 0 and TikTok tap lands near 1.8s.
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 input.mp4 output.mp4" >&2
  exit 2
fi
input_video="$1"
output_video="$2"
logo_frame="$(mktemp -t sleepblock-logo).png"
trap 'rm -f "$logo_frame"' EXIT

ffmpeg -hide_banner -loglevel error -y -ss 2.12 -i "$input_video" \
  -frames:v 1 "$logo_frame"
ffmpeg -hide_banner -loglevel error -y \
  -i "$input_video" -loop 1 -framerate 30 -t 1.4 -i "$logo_frame" \
  -filter_complex "[0:v]trim=start=0:end=1.95,setpts=PTS-STARTPTS[home];[1:v]trim=duration=1.4,setpts=PTS-STARTPTS,eq=saturation='max(0,1-t/1.4)':eval=frame,format=yuv420p[logo];[0:v]trim=start=3.5:end=6.5,setpts=PTS-STARTPTS[shield];[home][logo][shield]concat=n=3:v=1:a=0,fps=30,format=yuv420p[out]" \
  -map '[out]' -an -c:v libx264 -crf 20 -movflags +faststart "$output_video"
