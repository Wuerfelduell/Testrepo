#!/usr/bin/env bash
# Renders the arena with the inventory (tooltip shown) and the character sheet open.
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
for panel in inventory character; do
  status=0
  timeout 90 xvfb-run -a -s '-screen 0 1920x1080x24' \
    env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . res://scenes/arena/arena.tscn --rendering-method gl_compatibility \
    --audio-driver Dummy --disable-vsync --resolution 1920x1080 \
    -- --arena-capture="$PWD/build/ui-$panel.png" --ui-open="$panel" \
    > "build/ui-$panel.log" 2>&1 || status=$?
  cat "build/ui-$panel.log"
  if (( status != 0 )); then exit "$status"; fi
  if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' "build/ui-$panel.log" | \
    grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
    exit 1
  fi
  test -s "build/ui-$panel.png"
done
