#!/bin/bash
# Everything that must pass before a commit: a clean build, the core checks and the app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== stray copies"
# iCloud Drive leaves "File 2.swift" copies in synced folders; a stray copy would redeclare its types.
copies=$(find . -path ./.build -prune -o -path ./build -prune -o -path ./.git -prune -o -name '* [0-9].*' -print)
if [[ -n "$copies" ]]; then
    echo "$copies"
    echo "Delete these conflict copies first"
    exit 1
fi

echo "== format"
swift format lint --strict --parallel --recursive Package.swift Sources Checks scripts \
    || { echo "Formatting is off: run scripts/format.sh"; exit 1; }

echo "== build"
output="$(swift build -c release 2>&1)" || { echo "$output"; exit 1; }
if grep -q "warning:" <<<"$output"; then
    grep "warning:" <<<"$output" | sort -u
    echo "Build has warnings"
    exit 1
fi

echo "== core checks"
"$(swift build -c release --show-bin-path)/MixerCoreChecks"

echo "== app bundle"
scripts/build.sh >/dev/null
plist="build/VolumeMixer.app/Contents/Info.plist"
for key in NSAudioCaptureUsageDescription LSUIElement CFBundleIdentifier SUFeedURL SUPublicEDKey; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null || { echo "Info.plist is missing $key"; exit 1; }
done
[[ -d build/VolumeMixer.app/Contents/Frameworks/Sparkle.framework ]] || { echo "Sparkle.framework is missing"; exit 1; }
codesign --verify --deep --strict build/VolumeMixer.app
xmllint --noout docs/appcast.xml
echo "All checks passed"
