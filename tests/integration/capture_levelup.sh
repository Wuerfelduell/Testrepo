#!/usr/bin/env bash
# Renders the level-up screen (Fighter 2 and 4, Wizard 3) and the short rest dialog (prompt 08).
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
status=0
timeout 420 xvfb-run -a -s '-screen 0 1920x1080x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . res://tests/integration/check_levelup.tscn --rendering-method gl_compatibility \
  --audio-driver Dummy --disable-vsync --resolution 1920x1080 \
  -- --out="$PWD/build" > build/levelup.log 2>&1 || status=$?
cat build/levelup.log
if (( status != 0 )); then exit "$status"; fi
if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' build/levelup.log | \
  grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
  exit 1
fi
for name in levelup-button levelup-fighter-2 levelup-fighter-4 levelup-wizard-3 rest-short; do
  test -s "build/$name.png"
done
