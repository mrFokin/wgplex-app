#!/bin/bash
# Builds the release bundle and disk image (design 8, A5):
#   dist/Wgplex.app                universal (arm64 + x86_64), ad-hoc signed
#   dist/Wgplex-<VERSION>.dmg      + .sha256
# The version comes from VERSION and must equal `appVersion` in
# Sources/WgplexKit/Version.swift; the build fails on mismatch.
# usage: scripts/dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id=io.github.mrfokin.wgplex
dist=dist
app="$dist/Wgplex.app"

version=$(tr -d '[:space:]' < VERSION)
[ -n "$version" ] || { echo "dmg: VERSION is empty" >&2; exit 1; }

# appVersion is a single string literal: `public let appVersion = "x.y.z"`.
src_version=$(sed -n 's/^public let appVersion = "\(.*\)"$/\1/p' Sources/WgplexKit/Version.swift)
if [ "$version" != "$src_version" ]; then
    echo "dmg: VERSION ($version) != appVersion in Sources/WgplexKit/Version.swift (${src_version:-not found})" >&2
    exit 1
fi
# A pre-release suffix (e.g. -dev) is allowed for local test images, never for a release.
case "$version" in
    *-*) echo "dmg: warning: $version is a pre-release version, not for publishing" >&2 ;;
esac
# CFBundleVersion must be numeric: drop the pre-release suffix.
build=${version%%-*}

arch=(-c release --arch arm64 --arch x86_64)
swift build "${arch[@]}"
bin="$(swift build "${arch[@]}" --show-bin-path)/Wgplex"

rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Wgplex"
sed -e "s/@VERSION@/$version/" -e "s/@BUILD@/$build/" packaging/Info.plist > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null
cp packaging/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# Ad-hoc signature with an explicit designated requirement: the default one is the
# cdhash, which changes every build and breaks approval transfer on `brew upgrade` (design 8).
codesign --force --sign - -r="designated => identifier \"$bundle_id\"" "$app"
codesign --verify --strict "$app"

# The image holds the app and an /Applications link for drag-and-drop install.
stage="$dist/stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="Wgplex-$version.dmg"
hdiutil create -quiet -volname Wgplex -srcfolder "$stage" -format UDZO -ov "$dist/$dmg"
rm -rf "$stage"
(cd "$dist" && shasum -a 256 "$dmg" > "$dmg.sha256")

echo "$dist/$dmg"
cat "$dist/$dmg.sha256"
