#!/usr/bin/env bash
# Prompt 07: real Godot framebuffer captures of the M1 art (Xvfb + llvmpipe, the same
# software renderer the CI runner uses). No synthetic previews.
set -euo pipefail
cd "$(dirname "$0")/.."
godot_bin="${1:-godot}"
for view in overview enemies heroes weapons hits; do
  xvfb-run --auto-servernum --server-args='-screen 0 1280x720x24' \
    env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . res://scenes/showcase/asset_showcase.tscn --rendering-method gl_compatibility \
      --audio-driver Dummy --resolution 1280x720 -- --capture="$(pwd)/docs/m1-$view.png" "--m1-$view"
  test -s "docs/m1-$view.png"
done
