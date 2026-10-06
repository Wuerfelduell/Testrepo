#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
godot_bin="${1:-godot}"
mkdir -p build
for variant in exploration combat; do
  extra=()
  if [[ "$variant" == combat ]]; then extra+=(--arena-capture-combat); fi
  timeout 90 xvfb-run -a -s '-screen 0 1920x1080x24' \
    env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . --rendering-method gl_compatibility \
    --resolution 1920x1080 -- --arena-capture="$PWD/build/arena-$variant.png" "${extra[@]}" \
    > "build/arena-$variant.log" 2>&1
  cat "build/arena-$variant.log"
  if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' "build/arena-$variant.log"; then exit 1; fi
  test -s "build/arena-$variant.png"
done
