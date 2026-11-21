#!/bin/bash
# Finds the user-facing strings in the code and adds new ones to Resources/Localizable.xcstrings, as Xcode
# does when it builds. Translate what it adds: scripts/check.sh lists every string a language lacks.
# Needs Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/bundle.sh

work=$(mktemp -d "${TMPDIR:-/tmp}/smorza-strings.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/code" "$work/intents/Contents/Resources"
# The compiler lists every string handed to an API that localizes it.
swift build -c release --product Smorza -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$work/code" >/dev/null
# The phrases of the Shortcuts actions' summaries come from Apple's App Intents processor.
make_intents_metadata "$work/intents" "$work/intents/actions.stringsdata"

data=()
while IFS= read -r source; do
    file="$work/code/$(basename "$source" .swift).stringsdata"
    [[ -f "$file" ]] && data+=(--stringsdata "$file")
done < <(find Sources/Smorza -name "*.swift" | sort)
for file in "$work"/intents/*.stringsdata; do
    data+=(--stringsdata "$file")
done
xcrun xcstringstool sync Resources/Localizable.xcstrings "${data[@]}"
echo "Updated Resources/Localizable.xcstrings"
