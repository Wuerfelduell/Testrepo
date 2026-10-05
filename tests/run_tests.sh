#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
exec "${GODOT_BIN:-godot}" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit "$@"
