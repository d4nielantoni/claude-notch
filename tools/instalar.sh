#!/bin/bash
# instalar.sh — compila em Release e instala em /Applications.
#
# A reassinatura do pacote inteiro não é opcional: o MediaRemoteAdapter.framework
# vem pré-compilado e assinado pela equipe do upstream, e o dyld recusa carregar
# framework cujo Team ID difere do processo. Sem isto o app aborta no arranque.

set -e
cd "$(dirname "$0")/.."

APP=/Applications/boringNotch.app
REL=$(xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
        -configuration Release -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/boringNotch.app

echo "==> compilando Release"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination "platform=macOS" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3

echo "==> encerrando instâncias"
pkill -9 -f "MacOS/boringNotch" 2>/dev/null || true
sleep 2
rm -f "$HOME/Library/Containers/theboringteam.boringnotch/Data/tmp/cn.sock"

echo "==> instalando"
rm -rf "$APP"
cp -R "$REL" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> reassinando (de dentro para fora)"
for f in "$APP"/Contents/Frameworks/*.framework; do
  codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1
done
for x in "$APP"/Contents/XPCServices/*.xpc; do
  codesign --force --sign - --timestamp=none "$x" >/dev/null 2>&1
done
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/claude-notch-bridge" >/dev/null 2>&1
codesign --force --sign - --timestamp=none \
  --entitlements boringNotch/boringNotch.entitlements "$APP" >/dev/null 2>&1
codesign --verify --strict "$APP" && echo "    assinatura OK"

echo "==> subindo"
open -a "$APP"
sleep 6
if pgrep -f "/Applications/boringNotch.app/Contents/MacOS" >/dev/null; then
  echo "    app vivo"
else
  echo "    ERRO: o app não subiu"
  exit 1
fi
