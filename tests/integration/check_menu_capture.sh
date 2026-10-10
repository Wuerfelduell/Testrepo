#!/usr/bin/env bash
# Renders the menu loop on a virtual display: build/menu.png, creation.png, death.png.
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
status=0
timeout 240 xvfb-run -a -s '-screen 0 1920x1080x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . tests/integration/check_menu.tscn \
  --rendering-method gl_compatibility --audio-driver Dummy --disable-vsync --resolution 1920x1080 \
  -- --menu-capture-dir="$PWD/build" > build/menu-capture.log 2>&1 || status=$?
cat build/menu-capture.log
if (( status != 0 )); then exit "$status"; fi
if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' build/menu-capture.log | \
  grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
  exit 1
fi
for name in menu creation death; do test -s "build/$name.png"; done
