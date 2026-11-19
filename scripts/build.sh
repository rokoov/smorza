#!/bin/bash
# Builds build/VolumeMixer.app.
#   scripts/build.sh           build only
#   scripts/build.sh run       build and launch from build/
#   scripts/build.sh install   build, copy to /Applications and launch
# SIGN_IDENTITY picks a signing certificate; without one the app is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product VolumeMixer
source scripts/bundle.sh

APP="build/VolumeMixer.app"
products=$(swift build -c release --show-bin-path)
staged=$(make_app "$products/VolumeMixer" "$products/Sparkle.framework")
sign_app "$staged"
deliver_app "$staged" "$APP"
echo "Built $APP"

case "${1:-}" in
    run)
        pkill -x VolumeMixer 2>/dev/null || true
        open "$APP"
        echo "Launched $APP"
        ;;
    install)
        pkill -x VolumeMixer 2>/dev/null || true
        rm -rf /Applications/VolumeMixer.app
        ditto "$APP" /Applications/VolumeMixer.app
        open /Applications/VolumeMixer.app
        echo "Installed and launched /Applications/VolumeMixer.app"
        ;;
esac
