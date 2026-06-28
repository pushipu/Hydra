#!/bin/bash
# Генерирует все иконки из icon.svg: icon.icns для Hydra.app + PNG для расширений.
# Требует rsvg-convert (brew install librsvg) и iconutil (входит в macOS).
set -euo pipefail
cd "$(dirname "$0")"
SVG="icon.svg"
EXT_ICONS="../../extension/icons"

command -v rsvg-convert >/dev/null || { echo "нужен rsvg-convert: brew install librsvg"; exit 1; }

# --- macOS .icns ---
SET="Hydra.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  rsvg-convert -w "$s"     -h "$s"     "$SVG" -o "$SET/icon_${s}x${s}.png"
  rsvg-convert -w $((s*2)) -h $((s*2)) "$SVG" -o "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o icon.icns
rm -rf "$SET"
echo "✓ icon.icns"

# --- иконки расширений ---
mkdir -p "$EXT_ICONS"
for s in 16 32 48 128; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$EXT_ICONS/icon${s}.png"
done
echo "✓ extension/icons/icon{16,32,48,128}.png"
