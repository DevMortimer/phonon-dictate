#!/usr/bin/env bash
# Build "build/Phonon Dictate.app" (ad-hoc signed). Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/PhononDictate"

APP="build/Phonon Dictate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PhononDictate"
cp Info.plist "$APP/Contents/Info.plist"
cp python/worker.py python/requirements.txt "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Phonon Dictate.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Phonon Dictate.app"
fi
