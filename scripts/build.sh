#!/bin/bash
# Builds build/Smorza.app.
#   scripts/build.sh           build only
#   scripts/build.sh run       build and launch from build/
#   scripts/build.sh install   build, copy to /Applications and launch
# SIGN_IDENTITY picks a signing certificate, used with the hardened runtime; without one the app
# is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Smorza
source scripts/bundle.sh

APP="build/Smorza.app"
products=$(swift build -c release --show-bin-path)
staged=$(make_app "$products/Smorza" "$products/Sparkle.framework")
sign_app "$staged"
deliver_app "$staged" "$APP"
echo "Built $APP"

case "${1:-}" in
    run)
        pkill -x Smorza 2>/dev/null || true
        open "$APP"
        echo "Launched $APP"
        ;;
    install)
        pkill -x Smorza 2>/dev/null || true
        rm -rf /Applications/Smorza.app
        ditto "$APP" /Applications/Smorza.app
        open /Applications/Smorza.app
        echo "Installed and launched /Applications/Smorza.app"
        ;;
esac
