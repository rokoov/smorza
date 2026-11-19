#!/bin/bash
# Shared by build.sh and release.sh, which source it: puts VolumeMixer.app together and signs it.
#
# The bundle is assembled and signed in a temporary folder. In an iCloud-synced checkout the File
# Provider tags files with Finder info at any moment, and codesign refuses such files as detritus.

# make_app <binary> <Sparkle.framework>: prints the path of a new, unsigned VolumeMixer.app in a
# temporary folder.
make_app() {
    local binary=$1
    local sparkle=$2
    local staging
    staging=$(mktemp -d "${TMPDIR:-/tmp}/volume-mixer.XXXXXX")
    local app="$staging/VolumeMixer.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
    # Copied without extended attributes: they carry the Finder info that codesign refuses.
    cp -X "$binary" "$app/Contents/MacOS/VolumeMixer"
    cp -X Resources/Info.plist "$app/Contents/Info.plist"
    cp -X Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    plutil -lint "$app/Contents/Info.plist" >/dev/null

    local framework="$app/Contents/Frameworks/Sparkle.framework"
    ditto --norsrc --noextattr "$sparkle" "$framework"
    # Embedded like Xcode does: no headers or module maps, and no XPC services, which Sparkle only
    # needs for sandboxed apps (Volume Mixer is not sandboxed).
    for part in Headers PrivateHeaders Modules XPCServices; do
        rm -rf "${framework:?}/$part" "${framework:?}/Versions/B/$part"
    done
    echo "$app"
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
    sign "$app" --identifier com.rokoov.volumemixer
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
