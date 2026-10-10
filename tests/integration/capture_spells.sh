#!/usr/bin/env bash
# Renders the Wizard targeting and casting Burning Hands (prompt 05).
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
status=0
timeout 120 xvfb-run -a -s '-screen 0 1920x1080x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . res://tests/integration/capture_spells.tscn --rendering-method gl_compatibility \
  --audio-driver Dummy --disable-vsync --resolution 1920x1080 \
  -- --out="$PWD/build" > build/arena-spell.log 2>&1 || status=$?
cat build/arena-spell.log
if (( status != 0 )); then exit "$status"; fi
if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' build/arena-spell.log | \
  grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
  exit 1
fi
test -s build/arena-spell-target.png
test -s build/arena-spell-cast.png
