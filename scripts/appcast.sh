#!/bin/bash
# Signs a release zip with Sparkle's sign_update and adds it to docs/appcast.xml, newest first.
#   scripts/appcast.sh build/VolumeMixer-<version>.zip [notes.txt]
# The notes, plain text, are what the update window shows; without them it shows none.
# The EdDSA private key comes from the login keychain (made once with generate_keys, see
# docs/RELEASING.md), or from the file in SPARKLE_KEY_FILE. GitHub Pages serves docs/ from main, so
# the new entry goes live when the release reaches main. The zip must be uploaded to the GitHub
# Release v<version> under the same name, because that is the address the entry points to.
set -euo pipefail
cd "$(dirname "$0")/.."

zip=${1:?"usage: scripts/appcast.sh build/VolumeMixer-<version>.zip [notes.txt]"}
notes=${2:-}
[[ -f "$zip" ]] || { echo "No such file: $zip" >&2; exit 1; }
[[ -z "$notes" || -f "$notes" ]] || { echo "No such file: $notes" >&2; exit 1; }

plist=Resources/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist")
appcast=docs/appcast.xml
repository=https://github.com/rokoov/volume-mixer
marker="<!-- scripts/appcast.sh adds each release below this line, newest first -->"

if grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast"; then
    echo "$appcast already lists $version" >&2
    exit 1
fi

tools=$(scripts/sparkle-tools.sh)
# Prints the enclosure attributes: sparkle:edSignature="…" length="…"
signature=$("$tools/sign_update" ${SPARKLE_KEY_FILE:+--ed-key-file "$SPARKLE_KEY_FILE"} "$zip")

description=""
if [[ -n "$notes" ]]; then
    description="
      <description sparkle:descriptionFormat=\"plain-text\"><![CDATA[$(cat "$notes")]]></description>"
fi

item="    <item>
      <title>Version $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$repository/releases/tag/v$version</sparkle:fullReleaseNotesLink>$description
      <enclosure url=\"$repository/releases/download/v$version/$(basename "$zip")\" type=\"application/octet-stream\" $signature />
    </item>"

ITEM="$item" MARKER="$marker" awk '{ print } index($0, ENVIRON["MARKER"]) { print ENVIRON["ITEM"] }' "$appcast" \
    >"$appcast.new"
mv "$appcast.new" "$appcast"
xmllint --noout "$appcast"
echo "Added $version ($build) to $appcast"
