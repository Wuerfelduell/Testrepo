#!/usr/bin/env bash
# Real Godot framebuffer captures under a local/CI X server. No synthetic previews.
set -euo pipefail
cd "$(dirname "$0")/.."
godot_bin="${1:-godot}"
for view in normal closeup; do
  extra=()
  if [[ "$view" == closeup ]]; then extra+=(--enemy-closeup); fi
  xvfb-run --auto-servernum --server-args='-screen 0 1280x720x24' \
    env LIBGL_ALWAYS_SOFTWARE=1 "$godot_bin" --path . --rendering-method gl_compatibility \
      --audio-driver Dummy -- --capture="$(pwd)/docs/enemy-test-$view.png" "${extra[@]}"
done
if [[ "${2:-}" == --ci-transfer ]]; then
  python3 - <<'PY'
from pathlib import Path
import base64
for view in ['normal', 'closeup']:
    image = Path(f'docs/enemy-test-{view}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n')
    data = base64.b64encode(image).decode()
    print(f'ENEMY_PNG_BEGIN:{view}')
    for offset in range(0, len(data), 16384):
        print(f'ENEMY_PNG_DATA:{view}:' + data[offset:offset+16384])
    print(f'ENEMY_PNG_END:{view}')
PY
fi
