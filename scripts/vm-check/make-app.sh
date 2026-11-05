#!/bin/bash
# Builds a throwaway ad-hoc signed Wgplex.app from the SwiftPM build (for VM checks only;
# the release bundle is made by `make dmg`, A5).
# usage: make-app.sh <output-dir>   -> <output-dir>/Wgplex.app
set -euo pipefail
out=${1:?usage: make-app.sh <output-dir>}
cd "$(dirname "$0")/../.."
# SWIFT_SDK: optional SDK path (VM with only CLT needs the 26.5 SDK, see run-gui.sh)
sdk=()
[ -n "${SWIFT_SDK:-}" ] && sdk=(--sdk "$SWIFT_SDK")
swift build ${sdk[@]+"${sdk[@]}"} >&2
bin=$(swift build ${sdk[@]+"${sdk[@]}"} --show-bin-path)/Wgplex
app="$out/Wgplex.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Wgplex"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.mrfokin.wgplex</string>
  <key>CFBundleName</key><string>Wgplex</string>
  <key>CFBundleExecutable</key><string>Wgplex</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0-dev</string>
  <key>CFBundleVersion</key><string>0.1.0-dev</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - -r='designated => identifier "io.github.mrfokin.wgplex"' "$app"
echo "$app"
