#!/bin/bash
# install.sh — builds Release and installs into /Applications.
#
# Re-signing the whole bundle is not optional: MediaRemoteAdapter.framework ships
# prebuilt and signed by the upstream team, and dyld refuses to load a framework
# whose Team ID differs from the process. Without this the app aborts on launch.

set -e
cd "$(dirname "$0")/.."

APP=/Applications/boringNotch.app
REL=$(xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
        -configuration Release -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/boringNotch.app

echo "==> building Release"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination "platform=macOS" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3

echo "==> stopping running instances"
pkill -9 -f "MacOS/boringNotch" 2>/dev/null || true
sleep 2
rm -f "$HOME/Library/Containers/theboringteam.boringnotch/Data/tmp/cn.sock"

echo "==> installing"
rm -rf "$APP"
cp -R "$REL" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> re-signing (inside out)"
for f in "$APP"/Contents/Frameworks/*.framework; do
  codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1
done
for x in "$APP"/Contents/XPCServices/*.xpc; do
  codesign --force --sign - --timestamp=none "$x" >/dev/null 2>&1
done
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/claude-notch-bridge" >/dev/null 2>&1
codesign --force --sign - --timestamp=none \
  --entitlements boringNotch/boringNotch.entitlements "$APP" >/dev/null 2>&1
codesign --verify --strict "$APP" && echo "    signature OK"

echo "==> launching"
open -a "$APP"
sleep 6
if pgrep -f "/Applications/boringNotch.app/Contents/MacOS" >/dev/null; then
  echo "    app is running"
else
  echo "    ERROR: the app did not launch"
  exit 1
fi
