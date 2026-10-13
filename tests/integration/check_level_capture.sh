#!/usr/bin/env bash
# Package 10: screenshots of every crypt room, the combat HUD with rendered portraits,
# and the portrait check (needs a display, so it runs under Xvfb like the other captures).
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
run() {
  local name="$1"; shift
  local status=0
  timeout 150 xvfb-run -a -s '-screen 0 1920x1080x24' \
    env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . "$@" > "build/$name.log" 2>&1 || status=$?
  cat "build/$name.log"
  if (( status != 0 )); then exit "$status"; fi
  if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' "build/$name.log" | \
    grep -Fv 'WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'; then
    exit 1
  fi
}
common=(--rendering-method gl_compatibility --audio-driver Dummy --disable-vsync --resolution 1920x1080)
for room in vestibule hall corridor side_chamber ossuary rest shrine; do
  run "level-$room" res://scenes/levels/crypt/crypt.tscn "${common[@]}" -- --level-capture="$PWD/build/level-$room.png" --level-capture-room="$room"
  test -s "build/level-$room.png"
done
run level-combat res://scenes/levels/crypt/crypt.tscn "${common[@]}" -- --level-capture="$PWD/build/level-combat.png" --level-capture-combat
test -s build/level-combat.png
run level-portraits res://tests/integration/check_level_portraits.tscn "${common[@]}" -- --portraits-sheet="$PWD/build/level-portraits.png"
test -s build/level-portraits.png
