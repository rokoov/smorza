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

source scripts/bundle.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/volume-mixer-binary.XXXXXX")
binaries=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx$minimum"
    swift build -c release --product VolumeMixer --triple "$triple"
    # Copied at once: some SwiftPM versions put both architectures in the same output folder.
    cp "$(swift build -c release --product VolumeMixer --triple "$triple" --show-bin-path)/VolumeMixer" \
        "$work/VolumeMixer-$arch"
    binaries+=("$work/VolumeMixer-$arch")
done
joined="$work/VolumeMixer"
lipo -create "${binaries[@]}" -output "$joined"
staged=$(make_app "$joined")
rm -rf "$work"
sign_app "$staged"

# Zipped from the clean, signed copy, before it lands in a folder that may be synced.
zip="build/VolumeMixer-$version.zip"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$staged" "$zip"
lipo -info "$staged/Contents/MacOS/VolumeMixer"
deliver_app "$staged" build/release/VolumeMixer.app
shasum -a 256 "$zip"
