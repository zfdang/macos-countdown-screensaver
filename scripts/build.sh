#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
architecture="${1:-all}"
case "$architecture" in arm64|x86_64|all) ;; *) echo "Usage: $0 [arm64|x86_64|all]" >&2; exit 2 ;; esac
sdk=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p dist .build/distribution
python3 scripts/version.py > dist/build-info.json
version=$(python3 -c 'import json; print(json.load(open("dist/build-info.json"))["version"])')
core=(Sources/CountdownCore/*.swift)
ui=(Sources/CountdownUI/*.swift)
architectures=("$architecture")
if [[ "$architecture" == all ]]; then architectures=(arm64 x86_64); fi
for arch in "${architectures[@]}"; do
    root=".build/distribution/$arch"
    saver="$root/Countdown.saver"
    app="$root/Countdown Preview.app"
    mkdir -p "$saver/Contents/MacOS" "$app/Contents/MacOS"
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" -sdk "$sdk" \
        -module-name CountdownScreenSaver -emit-library "${core[@]}" "${ui[@]}" \
        -framework AppKit -framework ScreenSaver -o "$saver/Contents/MacOS/Countdown" \
        -Xlinker -install_name -Xlinker '@rpath/Countdown.saver/Contents/MacOS/Countdown'
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" -sdk "$sdk" -parse-as-library \
        -module-name CountdownPreview "${core[@]}" "${ui[@]}" Sources/CountdownPreview/PreviewMain.swift \
        -framework AppKit -framework ScreenSaver -o "$app/Contents/MacOS/CountdownPreview"
    python3 scripts/package-info.py "$root" "$arch"
    codesign --force --sign - "$saver"
    codesign --force --sign - "$app"
    codesign --verify --strict "$saver"
    codesign --verify --strict "$app"
    cp README.md LICENSE dist/build-info.json "$root/"
    ditto -c -k --keepParent "$saver" "dist/Countdown-$version-$arch.saver.zip"
    ditto -c -k --keepParent "$app" "dist/Countdown-$version-$arch.preview.zip"
    echo "Built $version ($arch)"
done
if [[ "$architecture" == all ]]; then
    root=.build/distribution/universal
    mkdir -p "$root"
    for name in Countdown.saver 'Countdown Preview.app'; do
        ditto ".build/distribution/arm64/$name" "$root/$name"
        executable=Countdown
        if [[ "$name" == 'Countdown Preview.app' ]]; then executable=CountdownPreview; fi
        xcrun lipo -create ".build/distribution/arm64/$name/Contents/MacOS/$executable" \
            ".build/distribution/x86_64/$name/Contents/MacOS/$executable" -output "$root/$name/Contents/MacOS/$executable"
        codesign --force --sign - "$root/$name"
        codesign --verify --strict "$root/$name"
    done
    ditto -c -k --keepParent "$root/Countdown.saver" "dist/Countdown-$version-universal.saver.zip"
    ditto -c -k --keepParent "$root/Countdown Preview.app" "dist/Countdown-$version-universal.preview.zip"
fi
(cd dist && shasum -a 256 ./*.zip > SHA256SUMS.txt)
