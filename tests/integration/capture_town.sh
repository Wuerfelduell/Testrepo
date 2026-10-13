#!/usr/bin/env bash
# Torviertel screenshots (gate, square, inn, alley, overview) under Xvfb into build/.
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
status=0
timeout 240 xvfb-run -a -s '-screen 0 1920x1080x24' env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . \
  res://tests/integration/capture_town.tscn --rendering-method gl_compatibility --audio-driver Dummy \
  --disable-vsync --resolution 1920x1080 -- --town-capture-dir="$PWD/build" > build/town-capture.log 2>&1 || status=$?
cat build/town-capture.log
if (( status != 0 )); then exit "$status"; fi
if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' build/town-capture.log | \
  grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
  exit 1
fi
for view in gate square inn alley overview; do test -s "build/town-$view.png"; done
