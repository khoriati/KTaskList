#!/usr/bin/env bash
# Compila em release e monta o bundle dist/KTaskList.app (assinatura ad-hoc).
# Uso: scripts/build-app.sh [--install]   (--install copia para /Applications)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/KTaskList.app"

cd "$ROOT"
swift build -c release 2>&1 | tail -3

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/KTaskList" "$APP/Contents/MacOS/KTaskList"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null
echo "Bundle gerado em: $APP"

if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "KTaskList" to quit' >/dev/null 2>&1 || true
  rm -rf "/Applications/KTaskList.app"
  cp -R "$APP" "/Applications/KTaskList.app"
  echo "Instalado em /Applications/KTaskList.app"
fi
