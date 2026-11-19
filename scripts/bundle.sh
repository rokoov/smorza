#!/bin/bash
# Shared by build.sh and release.sh, which source it: puts VolumeMixer.app together and signs it.
#
# The bundle is assembled and signed in a temporary folder. In an iCloud-synced checkout the File
# Provider tags files with Finder info at any moment, and codesign refuses such files as detritus.

# make_app <binary>: prints the path of a new, unsigned VolumeMixer.app in a temporary folder.
make_app() {
    local binary=$1
    local staging
    staging=$(mktemp -d "${TMPDIR:-/tmp}/volume-mixer.XXXXXX")
    local app="$staging/VolumeMixer.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$binary" "$app/Contents/MacOS/VolumeMixer"
    cp Resources/Info.plist "$app/Contents/Info.plist"
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    plutil -lint "$app/Contents/Info.plist" >/dev/null
    echo "$app"
}

# sign_app <app>: signs with SIGN_IDENTITY when set, ad hoc otherwise.
sign_app() {
    local app=$1
    codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.rokoov.volumemixer "$app"
    codesign --verify --strict "$app"
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
