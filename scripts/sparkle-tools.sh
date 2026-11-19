#!/bin/bash
# Prints the folder with Sparkle's command line tools (sign_update, generate_keys) for the Sparkle
# version pinned in Package.resolved. The SwiftPM package carries only the framework, so the tools
# come from that version's release archive, downloaded once into .build/sparkle-tools.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(awk '/"identity" : "sparkle"/ { found = 1 } found && /"version"/ { gsub(/[",]/, "", $3); print $3; exit }' \
    Package.resolved)
[[ -n "$version" ]] || { echo "Sparkle is not pinned in Package.resolved; run swift package resolve" >&2; exit 1; }

folder=".build/sparkle-tools/$version"
if [[ ! -x "$folder/bin/sign_update" ]]; then
    mkdir -p "$folder"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
        | tar -xJ -C "$folder" ./bin
    # The tools are signed ad hoc, so this only proves the download arrived whole.
    codesign --verify --strict "$folder/bin/sign_update" "$folder/bin/generate_keys" >&2
fi
echo "$PWD/$folder/bin"
