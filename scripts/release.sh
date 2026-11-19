#!/bin/bash
# Builds a universal (Apple silicon + Intel) Smorza.app, zips it for Sparkle and puts it in a disk
# image for the website, both for a GitHub Release.
#   scripts/release.sh    -> build/Smorza-<version>.zip and build/Smorza-<version>.dmg
#
#   SIGN_IDENTITY="Developer ID Application: <name> (<team>)" signs with that certificate and the
#   hardened runtime; without it the app is signed ad hoc and Gatekeeper blocks downloaded copies.
#   NOTARY_PROFILE=<profile> then has Apple notarize the zip, staples the ticket to the app and zips
#   it again, and does the same for the disk image. The profile is saved once with
#   `xcrun notarytool store-credentials` (docs/RELEASING.md).
#
# Command Line Tools cannot build several architectures in one go, so each is built on its own
# and the two binaries are joined with lipo.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGN_IDENTITY:-}" ]]; then
    echo "NOTARY_PROFILE needs SIGN_IDENTITY: Apple notarizes only apps signed with a Developer ID" >&2
    exit 1
fi

# notarize <zip or dmg>: uploads it to Apple's notary service and waits for the verdict. Anything
# but Accepted prints Apple's log, which names each file that failed and why.
notarize() {
    local file=$1
    local report id status
    # The verdict is read from notarytool's report rather than from its exit status.
    report=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
    id=$(plutil -extract id raw -o - - <<<"$report" 2>/dev/null) || id=""
    status=$(plutil -extract status raw -o - - <<<"$report" 2>/dev/null) || status=""
    if [[ "$status" != "Accepted" ]]; then
        echo "Notarization failed${status:+: $status}" >&2
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fi
        exit 1
    fi
    echo "Notarized, submission $id"
}

plist=Resources/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist")

source scripts/bundle.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/smorza-binary.XXXXXX")
binaries=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx$minimum"
    swift build -c release --product Smorza --triple "$triple"
    products=$(swift build -c release --product Smorza --triple "$triple" --show-bin-path)
    # Copied at once: some SwiftPM versions put both architectures in the same output folder.
    cp -X "$products/Smorza" "$work/Smorza-$arch"
    binaries+=("$work/Smorza-$arch")
    # Sparkle ships one universal framework, the same for both builds.
    sparkle="$products/Sparkle.framework"
done
joined="$work/Smorza"
lipo -create "${binaries[@]}" -output "$joined"
staged=$(make_app "$joined" "$sparkle")
rm -rf "$work"
sign_app "$staged"

# Zipped from the clean, signed copy, before it lands in a folder that may be synced.
zip="build/Smorza-$version.zip"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$staged" "$zip"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$zip"
    xcrun stapler staple "$staged"
    # Zipped again so the download carries the ticket and opens without Gatekeeper going online.
    rm -f "$zip"
    ditto -c -k --norsrc --noextattr --keepParent "$staged" "$zip"
    spctl --assess --type execute --verbose=2 "$staged"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "Not notarized: Gatekeeper blocks downloaded copies until it is (set NOTARY_PROFILE)" >&2
fi

# The disk image the website hands out: the finished app and a link to drag it onto Applications.
# Sparkle keeps updating from the zip.
dmg="build/Smorza-$version.dmg"
dmg_folder=$(mktemp -d "${TMPDIR:-/tmp}/smorza-dmg.XXXXXX")
ditto --norsrc --noextattr "$staged" "$dmg_folder/Smorza.app"
ln -s /Applications "$dmg_folder/Applications"
hdiutil create -volname "Smorza" -srcfolder "$dmg_folder" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg"
rm -rf "$dmg_folder"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$dmg"
    xcrun stapler staple "$dmg"
fi

lipo -info "$staged/Contents/MacOS/Smorza" "$staged/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
deliver_app "$staged" build/release/Smorza.app
shasum -a 256 "$zip" "$dmg"
