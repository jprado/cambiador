#!/usr/bin/env bash
# build-release.sh — Build Cambiador.app (Release) and package it into a DMG.
#
# Usage:
#   ./scripts/build-release.sh              # uses version from Info.plist
#   ./scripts/build-release.sh 1.2.0        # override version string
#
# Output:
#   dist/Cambiador-v<VERSION>.dmg
#
# Requirements: Xcode command-line tools (xcode-select --install)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Cambiador.xcodeproj"
SCHEME="Cambiador"
BUILD_DIR="$REPO_ROOT/.build/release"
DIST_DIR="$REPO_ROOT/dist"
DMG_STAGING="$REPO_ROOT/.build/dmg-staging"

# Clean up temp dirs on failure
trap 'rm -rf "$BUILD_DIR" "$DMG_STAGING"' ERR

# ── Version ──────────────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    VERSION="$1"
else
    # Read CFBundleShortVersionString from Info.plist
    PLIST="$REPO_ROOT/Cambiador/Info.plist"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST" 2>/dev/null || true)
    if [[ -z "$VERSION" ]]; then
        echo "❌  Could not determine version from Info.plist. Pass it as an argument: $0 <version>"
        exit 1
    fi
fi

# Guard: make sure VERSION looks like a real version number
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9] ]]; then
    echo "ERROR: Version '${VERSION}' doesn't look like a version number."
    echo "       Pass it explicitly: $0 <version>  (e.g. $0 1.0.0)"
    exit 1
fi

DMG_NAME="Cambiador-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "Building Cambiador v${VERSION} (Release)..."

# ── Clean previous artifacts ─────────────────────────────────────────────────
rm -rf "$BUILD_DIR" "$DMG_STAGING"

# ── xcodebuild ───────────────────────────────────────────────────────────────
XCBUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration Release
    -derivedDataPath "$REPO_ROOT/.build/derived"
    SYMROOT="$BUILD_DIR"
    CODE_SIGN_IDENTITY="-"
    ARCHS="arm64 x86_64"
    ONLY_ACTIVE_ARCH=NO
)

if command -v xcbeautify &>/dev/null; then
    set -o pipefail
    xcodebuild "${XCBUILD_ARGS[@]}" build 2>&1 | xcbeautify
else
    xcodebuild "${XCBUILD_ARGS[@]}" build -quiet
fi

# Locate the built .app
APP_PATH=$(find "$BUILD_DIR" -name "Cambiador.app" -maxdepth 3 | head -1)
if [[ -z "$APP_PATH" ]]; then
    echo "❌  Build succeeded but Cambiador.app not found under $BUILD_DIR"
    exit 1
fi
echo "✅  Built: $APP_PATH"

# ── Stage DMG contents ───────────────────────────────────────────────────────
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/Cambiador.app"
# Symlink to Applications so drag-install works
ln -s /Applications "$DMG_STAGING/Applications"

# ── Create DMG ───────────────────────────────────────────────────────────────
mkdir -p "$DIST_DIR"

echo "Creating ${DMG_NAME}..."
hdiutil create \
    -volname "Cambiador v${VERSION}" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# ── Checksum ─────────────────────────────────────────────────────────────────
SHA256_PATH="${DMG_PATH}.sha256"
shasum -a 256 "$DMG_PATH" > "$SHA256_PATH"
echo "SHA256: $(cat "$SHA256_PATH")"

echo ""
echo "🎉  Done! Release artifact:"
echo "    $DMG_PATH"
echo ""
echo "Next steps:"
echo "  1. Test the DMG:       open \"$DMG_PATH\""
echo "  2. Tag the release:    git tag v${VERSION} && git push origin v${VERSION}"
echo "  3. Go to https://github.com/jprado/cambiador/releases/new"
echo "     → Choose tag v${VERSION}, attach $DMG_NAME and $DMG_NAME.sha256, publish."
