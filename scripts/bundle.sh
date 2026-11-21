#!/bin/bash
# Shared by build.sh and release.sh, which source it: puts Smorza.app together and signs it.
#
# The bundle is assembled and signed in a temporary folder. In an iCloud-synced checkout the File
# Provider tags files with Finder info at any moment, and codesign refuses such files as detritus.

# make_app <binary> <Sparkle.framework> [resource bundles...]: prints the path of a new, unsigned
# Smorza.app in a temporary folder.
make_app() {
    local binary=$1
    local sparkle=$2
    shift 2
    local staging
    staging=$(mktemp -d "${TMPDIR:-/tmp}/smorza.XXXXXX")
    local app="$staging/Smorza.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
    # Copied without extended attributes: they carry the Finder info that codesign refuses.
    cp -X "$binary" "$app/Contents/MacOS/Smorza"
    cp -X Resources/Info.plist "$app/Contents/Info.plist"
    cp -X Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    # The packages built into the app are MIT licensed, and their notices travel with every copy.
    mkdir -p "$app/Contents/Resources/Licenses"
    cp -X .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Licenses/Sparkle.txt"
    cp -X .build/checkouts/KeyboardShortcuts/license "$app/Contents/Resources/Licenses/KeyboardShortcuts.txt"
    make_intents_metadata "$app"
    make_localizations "$app"
    # SwiftPM resource bundles (a package's localized strings) go where Bundle.module looks first;
    # a missing one stops the app the moment the package needs it.
    local resources
    for resources in "$@"; do
        ditto --norsrc --noextattr "$resources" "$app/Contents/Resources/$(basename "$resources")"
    done
    plutil -lint "$app/Contents/Info.plist" >/dev/null

    local framework="$app/Contents/Frameworks/Sparkle.framework"
    ditto --norsrc --noextattr "$sparkle" "$framework"
    # Embedded like Xcode does: no headers or module maps, and no XPC services, which Sparkle only
    # needs for sandboxed apps (Smorza is not sandboxed).
    for part in Headers PrivateHeaders Modules XPCServices; do
        rm -rf "${framework:?}/$part" "${framework:?}/Versions/B/$part"
    done
    echo "$app"
}

# make_intents_metadata <app> [stringsdata]: Shortcuts reads an app's actions from Metadata.appintents, which
# Xcode builds from the constant values the compiler wrote; Package.swift asks for them in release builds.
# Without Xcode's metadata processor the app still works, with no actions in Shortcuts. With a second
# argument the processor also writes the actions' strings for the String Catalog next to that path.
make_intents_metadata() {
    local app=$1
    local strings=()
    [[ -n "${2:-}" ]] && strings=(--stringsdata-file "$2")
    local constvalues="$PWD/.build/Smorza.swiftconstvalues"
    if [[ ! -f "$constvalues" ]] || ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
        echo "No App Intents metadata: Shortcuts will not list the app's actions (needs Xcode)" >&2
        return
    fi
    local lists minimum toolchain
    lists=$(mktemp -d "${TMPDIR:-/tmp}/smorza-intents.XXXXXX")
    find "$PWD/Sources/Smorza" -name "*.swift" | sort >"$lists/sources"
    echo "$constvalues" >"$lists/constvalues"
    minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)
    toolchain=$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")
    xcrun appintentsmetadataprocessor --output "$app/Contents/Resources" --toolchain-dir "$toolchain" \
        --module-name Smorza --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" --platform-family macOS \
        --deployment-target "$minimum" --target-triple "arm64-apple-macosx$minimum" \
        --source-file-list "$lists/sources" --swift-const-vals-list "$lists/constvalues" \
        --force --deployment-aware-processing --no-app-shortcuts-localization ${strings[@]+"${strings[@]}"} >&2 2>/dev/null
    rm -rf "$lists"
}

# make_localizations <app>: compiles the String Catalogs in Resources into a strings file per language,
# as Xcode would. Without Xcode's xcstringstool the app is in English only.
make_localizations() {
    local resources="$1/Contents/Resources"
    if ! xcrun --find xcstringstool >/dev/null 2>&1; then
        echo "No translations: the app will be in English only (needs Xcode)" >&2
        return
    fi
    local catalog
    for catalog in Resources/*.xcstrings; do
        xcrun xcstringstool compile "$catalog" --output-directory "$resources" >/dev/null
    done
    # English needs a folder of its own, or a Mac set to English with German second would pick German.
    mkdir -p "$resources/en.lproj"
}

# sign <path> [codesign options]: signs one item with SIGN_IDENTITY, the hardened runtime and a
# secure timestamp, as notarization requires, or ad hoc without an identity. Ad hoc builds leave the
# runtime off: its library validation would refuse the ad hoc signed Sparkle.framework.
sign() {
    local path=$1
    shift
    if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@" "$path"
    else
        codesign --force --sign - "$@" "$path"
    fi
}

# sign_app <app>: signs from the inside out, as codesign requires: Sparkle's helpers, the
# framework, then the app.
sign_app() {
    local app=$1
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    sign "$framework/Versions/B/Autoupdate"
    sign "$framework/Versions/B/Updater.app"
    sign "$framework"
    sign "$app" --identifier com.rokoov.smorza
    codesign --verify --deep --strict "$app"
}

# deliver_app <app> <destination>: copies the signed app out of its temporary folder.
deliver_app() {
    local app=$1
    local destination=$2
    rm -rf "$destination"
    mkdir -p "$(dirname "$destination")"
    ditto --norsrc --noextattr "$app" "$destination"
    rm -rf "$(dirname "$app")"
}
