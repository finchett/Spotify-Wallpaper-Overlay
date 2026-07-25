#!/bin/bash
# Builds a release binary and wraps it in a signed SpotifyWallpaper.app bundle.
# Usage:  ./package.sh          build the .app into ./build
#         ./package.sh --install  also copy it to /Applications
set -euo pipefail

APP_NAME="SpotifyWallpaper"
BUNDLE_ID="com.samfinchett.spotifywallpaper"
VERSION="1.0"
RELEASE_BIN=".build/release/${APP_NAME}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${RELEASE_BIN}" "${CONTENTS}/MacOS/${APP_NAME}"

echo "==> Generating app icon"
ICONSET="build/AppIcon.iconset"
rm -rf "${ICONSET}"
swift make-icon.swift "${ICONSET}"
iconutil -c icns "${ICONSET}" -o "${CONTENTS}/Resources/AppIcon.icns"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Spotify Wallpaper</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>SpotifyWallpaper reads the currently playing track from the Spotify app.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP_DIR}"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"
    echo "==> Installed. Launch it:  open -a ${APP_NAME}"
else
    echo "==> Built ${APP_DIR}"
    echo "    Install with:  ./package.sh --install"
fi
