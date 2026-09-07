#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY=0
REVIEW=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify) VERIFY=1 ;;
        --review) REVIEW=1 ;;
        *) echo "Usage: $0 [--verify] [--review]" >&2; exit 2 ;;
    esac
    shift
done
APP_NAME="ARCHi Desktop Preview"
APP_IDENTIFIER="com.quotient.archi.desktop.preview"
APP_DIR="/private/tmp/archi-desktop-preview-${UID}/$APP_NAME.app"
PREVIOUS_EXECUTABLE="$REPO_ROOT/output/native/ARCHi Desktop Preview.app/Contents/MacOS/ARCHiDesktop"
if [[ "$REVIEW" == 1 ]]; then
    # A separate bundle lets development QA leave the user's open session intact.
    APP_NAME="ARCHi Development Review"
    APP_IDENTIFIER="com.quotient.archi.desktop.review"
    APP_DIR="/private/tmp/archi-desktop-review-${UID}/$APP_NAME.app"
    PREVIOUS_EXECUTABLE=""
fi
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/ARCHiDesktop"

require_selected_app_stopped() {
    local process_id process_command process_ids query_status
    if process_ids="$(pgrep -x ARCHiDesktop)"; then
        :
    else
        query_status=$?
        if [[ "$query_status" != 1 ]]; then
            echo "Could not check whether $APP_NAME is running. No app files were replaced; quit the selected app and retry with process inspection available." >&2
            return 1
        fi
    fi
    while IFS= read -r process_id; do
        [[ -n "$process_id" ]] || continue
        process_command="$(ps -p "$process_id" -o comm= 2>/dev/null || true)"
        if [[ "$process_command" == "$APP_EXECUTABLE" ||
              ( -n "$PREVIOUS_EXECUTABLE" && "$process_command" == "$PREVIOUS_EXECUTABLE" ) ]]; then
            echo "$APP_NAME is still running. This build will not replace its open session." >&2
            echo "Export any working draft, save the choices you want to keep, then choose Quit in $APP_NAME. Wait for it to close and rerun this command." >&2
            return 1
        fi
    done <<< "$process_ids"
}

# Preserve the selected profile's owned requests and unsaved work. The user
# quits through the app so its normal Habitat, model and Reactor cleanup runs.
require_selected_app_stopped

# Build the same TypeScript/Vite production entry into a private staging folder.
# The user's currently served browser dist is preserved during native review.
PLAY_STAGE="$(mktemp -d /private/tmp/archi-play-bundle.XXXXXX)"
trap 'rm -rf "$PLAY_STAGE"' EXIT
(cd "$REPO_ROOT" && npm exec -- tsc --noEmit && npm exec -- vite build --outDir "$PLAY_STAGE/Play")
mkdir -p "$PLAY_STAGE/Play/pwa/icons"
cp "$REPO_ROOT/pwa/manifest.webmanifest" "$PLAY_STAGE/Play/pwa/manifest.webmanifest"
cp "$REPO_ROOT"/pwa/icons/*.png "$PLAY_STAGE/Play/pwa/icons/"
# The native host owns asset availability and intentionally has no service worker.
test -f "$PLAY_STAGE/Play/index.html"
test ! -e "$PLAY_STAGE/Play/service-worker.js"

swift build --package-path "$REPO_ROOT/desktop"
if [[ "$VERIFY" == 1 ]]; then swift test --package-path "$REPO_ROOT/desktop"; fi
BIN_DIR="$(swift build --package-path "$REPO_ROOT/desktop" --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
# Building can take time. Recheck in case this profile was opened meanwhile,
# immediately before replacing its executable or generated resources.
require_selected_app_stopped
cp "$BIN_DIR/ARCHiDesktop" "$APP_EXECUTABLE"
# Replace only the generated game resources in this selected development bundle.
if [[ -e "$APP_DIR/Contents/Resources/Play" ]]; then
    mv "$APP_DIR/Contents/Resources/Play" "$PLAY_STAGE/PreviousPlay"
fi
cp -R "$PLAY_STAGE/Play" "$APP_DIR/Contents/Resources/Play"
# The native art loader uses this packaged location, never a development fallback.
if [[ -e "$APP_DIR/Contents/Resources/CompanionArt" ]]; then
    mv "$APP_DIR/Contents/Resources/CompanionArt" "$PLAY_STAGE/PreviousCompanionArt"
fi
cp -R "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/CompanionArt" "$APP_DIR/Contents/Resources/CompanionArt"
test -f "$APP_DIR/Contents/Resources/CompanionArt/archi-pearl-study-v1.png"
mkdir -p "$APP_DIR/Contents/Resources/ReactorBridge"
cp "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/ReactorBridge/worker.py" "$APP_DIR/Contents/Resources/ReactorBridge/worker.py"
# A native button has the app's filesystem access, not Codex's Documents access.
# Copy the already-installed runtime into this generated app so Python startup
# never waits on a repository-local pyvenv.cfg or site-packages privacy prompt.
REACTOR_SOURCE_RUNTIME="$REPO_ROOT/output/creative-tools/reactor/runtime"
REACTOR_APP_RUNTIME="$APP_DIR/Contents/Resources/ReactorRuntime"
if [[ -d "$REACTOR_APP_RUNTIME" ]]; then
    mv "$REACTOR_APP_RUNTIME" "$PLAY_STAGE/PreviousReactorRuntime"
fi
if [[ -x "$REACTOR_SOURCE_RUNTIME/bin/python3" ]]; then
    # Copy interpreter launchers by value: signed app bundles cannot contain
    # symlinks escaping to the external Python framework.
    cp -RL "$REACTOR_SOURCE_RUNTIME" "$REACTOR_APP_RUNTIME"
fi
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>ARCHiDesktop</string>
<key>CFBundleIdentifier</key><string>$APP_IDENTIFIER</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.7.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>ARCHiReactorPython</key><string>$REACTOR_APP_RUNTIME/bin/python3</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
# Finder may attach metadata after a preview is opened; remove it only from this
# regenerated development bundle before signing the next build.
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
open -n "$APP_DIR"
echo "Built and requested launch: $APP_DIR"
