#!/bin/sh
# Re-export the web build for local testing (then just reload the page): sh tools/export.sh
cd "$(dirname "$0")/.." && "C:/Users/josh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release Web build/web/index.html 2>&1 | grep -i "error" ; echo exported
