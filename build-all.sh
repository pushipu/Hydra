#!/usr/bin/env bash
# Единая сборка Hydra: 1 приложение + готовые к установке расширения.
#
#   ./build-all.sh
#
# Результат в dist/:
#   Hydra.app            — приложение (host вложен внутрь, сам регистрируется)
#   chrome/              — папка для «Загрузить распакованное» (chrome://extensions)
#   hydra-chrome.zip     — то же, упаковано
#   hydra-firefox.xpi    — установка через about:debugging или подписанный AMO
#
# Связка app↔расширение происходит сама: при первом запуске Hydra.app пишет
# native-messaging манифесты во все браузеры (HostRegistrar.swift). Юзеру нужно
# только запустить app и поставить расширение своего браузера.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
EXT="$ROOT/extension"

# --- 0. Guard: ключ в manifest.chrome.json должен давать тот же id, что вшит в host. ---
KEY=$(python3 -c "import json,sys; print(json.load(open('$EXT/manifest.chrome.json'))['key'])")
DERIVED=$(printf '%s' "$KEY" | base64 -D 2>/dev/null | openssl dgst -sha256 -binary | python3 -c "
import sys; b=sys.stdin.buffer.read()[:16]; print(''.join(chr(ord('a')+int(c,16)) for c in b.hex()))")
BAKED=$(grep -oE 'chromeExtensionID = \"[a-p]{32}\"' "$ROOT/core/Sources/HydraApp/HostRegistrar.swift" | grep -oE '[a-p]{32}')
if [ "$DERIVED" != "$BAKED" ]; then
  echo "✗ Рассинхрон Chrome id: manifest.key→$DERIVED, а в HostRegistrar.swift вшит $BAKED" >&2
  echo "  Обнови chromeExtensionID в HostRegistrar.swift на $DERIVED." >&2
  exit 1
fi
echo "▸ Chrome extension id: $DERIVED ✓"

# --- 1. Приложение (вкладывает host + само-регистрация). ---
echo "▸ Сборка Hydra.app…"
"$ROOT/app/build.sh"
rm -rf "$DIST/Hydra.app"
mkdir -p "$DIST"
# ditto, не cp -R: корректно переносит code signature бандла.
ditto "$ROOT/app/Hydra.app" "$DIST/Hydra.app"

# --- 1b. Нотаризация (только если задан профиль notarytool). ---
# Без неё .app, скачанный с интернета, на чужой машине ловит «повреждена»
# (quarantine + Gatekeeper). С Developer ID + нотаризацией + staple — запускается
# у всех без предупреждений и без снятия quarantine вручную.
# Подготовка один раз:
#   xcrun notarytool store-credentials hydra --apple-id <你@почта> \
#     --team-id <TEAMID> --password <app-specific-password>
# Сборка для раздачи:
#   HYDRA_SIGN_ID="Developer ID Application: …" HYDRA_NOTARY_PROFILE=hydra ./build-all.sh
if [ -n "${HYDRA_NOTARY_PROFILE:-}" ]; then
  echo "▸ Нотаризация (профиль: $HYDRA_NOTARY_PROFILE)…"
  ZIP="$DIST/Hydra-notarize.zip"
  ditto -c -k --keepParent "$DIST/Hydra.app" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$HYDRA_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DIST/Hydra.app"
  rm -f "$ZIP"
  spctl -a -t exec -vv "$DIST/Hydra.app"   # должно быть: accepted, source=Notarized Developer ID
else
  echo "▸ Нотаризация пропущена (HYDRA_NOTARY_PROFILE не задан) — .app только для своей машины."
fi

# --- 2. Расширения: общий src + иконки, разные манифесты. ---
pack() { # <target-manifest> <staging-dir>
  local manifest="$1" stage="$2"
  rm -rf "$stage"; mkdir -p "$stage"
  cp -R "$EXT/src" "$EXT/icons" "$stage/"
  cp "$EXT/$manifest" "$stage/manifest.json"
}

echo "▸ Пакет Chrome…"
pack manifest.chrome.json "$DIST/chrome"
( cd "$DIST/chrome" && zip -qr "$DIST/hydra-chrome.zip" . )

echo "▸ Пакет Firefox…"
pack manifest.firefox.json "$DIST/firefox"
( cd "$DIST/firefox" && zip -qr "$DIST/hydra-firefox.xpi" . )
rm -rf "$DIST/firefox"

cat <<EOF

✓ Готово. dist/:
  Hydra.app          → перетащи в /Applications и запусти (один раз)
  chrome/            → chrome://extensions → Режим разработчика → Загрузить распакованное
  hydra-chrome.zip   → то же, в архиве
  hydra-firefox.xpi  → about:debugging → Загрузить временное дополнение (или подпиши в AMO)

Связывать вручную ничего не нужно: app сам прописал host во все браузеры.
EOF
