#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
arch="${1:-$(uname -m)}"
output="${2:-.acceptance}"
mkdir -p "$output"
output=$(cd "$output" && pwd)
root="$(pwd)/.build/distribution/$arch"
"$root/Countdown Preview.app/Contents/MacOS/CountdownPreview" --acceptance --output "$output"
"$root/Countdown Preview.app/Contents/MacOS/CountdownPreview" --acceptance-close
"$root/Countdown Preview.app/Contents/MacOS/CountdownPreview" --acceptance-preferences
xcrun swiftc -swift-version 5 -target "$arch-apple-macos13.0" -parse-as-library Tools/AcceptanceHost.swift -framework AppKit -framework ScreenSaver -o ".build/AcceptanceHost-$arch"
".build/AcceptanceHost-$arch" "$root/Countdown.saver" "$output"
xcrun lipo "$root/Countdown.saver/Contents/MacOS/Countdown" -verify_arch "$arch"
xcrun lipo "$root/Countdown Preview.app/Contents/MacOS/CountdownPreview" -verify_arch "$arch"
plutil -lint "$root/Countdown.saver/Contents/Info.plist" "$root/Countdown Preview.app/Contents/Info.plist"
codesign --verify --strict "$root/Countdown.saver"
codesign --verify --strict "$root/Countdown Preview.app"
echo "PASS: $arch architecture, bundle metadata and signatures"
