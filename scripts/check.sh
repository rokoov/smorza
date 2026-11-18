#!/bin/bash
# Everything that must pass before a commit: a clean build, the core checks and the app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

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
for key in NSAudioCaptureUsageDescription LSUIElement CFBundleIdentifier; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null || { echo "Info.plist is missing $key"; exit 1; }
done
codesign --verify build/VolumeMixer.app
echo "All checks passed"
