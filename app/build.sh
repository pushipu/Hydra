#!/bin/bash
# Собирает Hydra.app из SwiftPM executable
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/core"
# host собираем вместе с app — он вкладывается внутрь bundle, и при запуске app
# сам регистрирует его в браузерах (HostRegistrar.swift). Отдельный install.sh не нужен.
# swift build берёт только один --product, поэтому собираем все продукты разом.
swift build -c release

APP="$ROOT/app/Hydra.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/"{MacOS,Resources}

cp .build/release/HydraApp "$APP/Contents/MacOS/Hydra"
cp .build/release/hydra-host "$APP/Contents/Resources/hydra-host"
cp "$ROOT/app/Hydra/icon.icns" "$APP/Contents/Resources/icon.icns"
cp "$ROOT/app/Hydra/Info.plist" "$APP/Contents/Info.plist"

# Вкладываем готовые расширения внутрь app, чтобы ставить их прямо из приложения,
# пока они не в магазинах. Кладём в Resources/Extensions до подписи bundle.
EXT="$ROOT/extension"
EXTDST="$APP/Contents/Resources/Extensions"
mkdir -p "$EXTDST/chrome"
cp -R "$EXT/src" "$EXT/icons" "$EXTDST/chrome/"
cp "$EXT/manifest.chrome.json" "$EXTDST/chrome/manifest.json"
FX="$(mktemp -d)"
cp -R "$EXT/src" "$EXT/icons" "$FX/"
cp "$EXT/manifest.firefox.json" "$FX/manifest.json"
( cd "$FX" && zip -qr "$EXTDST/hydra-firefox.xpi" . )
rm -rf "$FX"

# Переподписываем весь bundle. SwiftPM ставит бинарю linker-signed подпись как
# standalone-бинарю; после вкладывания в .app + Resources она перестаёт
# соответствовать структуре → Gatekeeper: «повреждена или не содержит компонентов».
# Подписываем изнутри наружу: сначала вложенный host, потом весь bundle (подпись
# bundle сама покрывает главный бинарь и печатает _CodeSignature/CodeResources).
#
# HYDRA_SIGN_ID не задан → ad-hoc (-s -): хватает для своей машины.
# HYDRA_SIGN_ID="Developer ID Application: …" → подпись для раздачи: добавляем
# Hardened Runtime (--options runtime) и secure timestamp — обязательны для
# нотаризации. Саму нотаризацию делает build-all.sh.
SIGN_ID="${HYDRA_SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  codesign --force -s - "$APP/Contents/Resources/hydra-host"
  codesign --force -s - "$APP"
else
  # Hardened Runtime + secure timestamp обязательны для нотаризации.
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP/Contents/Resources/hydra-host"
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP"
fi
codesign --verify --strict "$APP"   # падаем сразу, если bundle снова невалиден
echo "  подписано: $SIGN_ID"

echo "✓ Hydra.app готов: $APP"
echo "  Запуск: open $APP"
