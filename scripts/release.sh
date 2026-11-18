#!/bin/bash
# Builds a universal (Apple silicon + Intel) VolumeMixer.app and zips it for a GitHub Release.
#   scripts/release.sh    -> build/VolumeMixer-<version>.zip
# Command Line Tools cannot build several architectures in one go, so each is built on its own
# and the two binaries are joined with lipo.
set -euo pipefail
cd "$(dirname "$0")/.."

plist=Resources/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist")

binaries=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx$minimum"
    swift build -c release --product VolumeMixer --triple "$triple"
    binaries+=("$(swift build -c release --product VolumeMixer --triple "$triple" --show-bin-path)/VolumeMixer")
done

app=build/release/VolumeMixer.app
rm -rf build/release
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/VolumeMixer"
cp "$plist" "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.rokoov.volumemixer "$app"
codesign --verify "$app"

zip="build/VolumeMixer-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
lipo -info "$app/Contents/MacOS/VolumeMixer"
shasum -a 256 "$zip"
