#!/usr/bin/env bash
# Verifica os pré-requisitos para compilar o KTaskList e aponta como instalar o que faltar.
# Uso: scripts/check-env.sh        (sai com código 1 se algo essencial faltar)
set -uo pipefail

ok=0; fail=0
pass() { echo "  ✔ $1"; ok=$((ok+1)); }
miss() { echo "  ✖ $1"; echo "    → $2"; fail=$((fail+1)); }

echo "KTaskList — verificação de ambiente"

if [ "$(uname -s)" = "Darwin" ]; then
  ver="$(sw_vers -productVersion)"
  major="${ver%%.*}"
  if [ "$major" -ge 14 ]; then pass "macOS $ver (mínimo 14 Sonoma)"
  else miss "macOS $ver é anterior ao 14" "O app usa MenuBarExtra(.window), onKeyPress e ContentUnavailableView (macOS 14+)."; fi
else
  miss "Sistema $(uname -s) não é macOS" "O KTaskList é um app nativo macOS (SwiftUI/AppKit); só compila em macOS."
fi

if xcode-select -p >/dev/null 2>&1; then pass "Command Line Tools / Xcode em $(xcode-select -p)"
else miss "Command Line Tools ausentes" "Execute: xcode-select --install   (ou instale o Xcode pela App Store)"; fi

if command -v swift >/dev/null 2>&1; then
  sv="$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+\.[0-9]+' | head -1 | awk '{print $3}')"
  smajor="${sv%%.*}"; sminor="${sv#*.}"
  if [ -n "$sv" ] && { [ "$smajor" -gt 5 ] || { [ "$smajor" -eq 5 ] && [ "$sminor" -ge 9 ]; }; }; then pass "Swift $sv (mínimo 5.9)"
  else miss "Swift ${sv:-desconhecido} é anterior a 5.9" "Atualize o Xcode (15+) ou as Command Line Tools."; fi
else
  miss "swift não encontrado no PATH" "Instale o Xcode 15+ ou as Command Line Tools: xcode-select --install"
fi

if command -v codesign >/dev/null 2>&1; then pass "codesign disponível (assinatura ad-hoc do bundle)"
else miss "codesign ausente" "Vem com as Command Line Tools: xcode-select --install"; fi

echo
if [ "$fail" -eq 0 ]; then
  echo "Tudo pronto. Próximos passos: swift build && swift test && scripts/build-app.sh --install"
else
  echo "$fail pendência(s). Resolva acima e rode novamente."
  exit 1
fi
