#!/bin/bash
# Builds a release binary and wraps it in a signed SpotifyWallpaper.app bundle.
# Usage:  ./package.sh
#         ./package.sh --install
#         ./package.sh --version 1.2.3 --universal --archive
set -euo pipefail

APP_NAME="SpotifyWallpaper"
BUNDLE_ID="com.samfinchett.spotifywallpaper"
VERSION="1.0.0"
RELEASE_BIN=".build/release/${APP_NAME}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
INSTALL=false
ARCHIVE=false
UNIVERSAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL=true
            shift
            ;;
        --archive)
            ARCHIVE=true
            shift
            ;;
        --universal)
            UNIVERSAL=true
            shift
            ;;
        --version)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "error: --version requires a value" >&2
                exit 1
            fi
            VERSION="${2#v}"
            shift 2
            ;;
        *)
            echo "error: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ "${UNIVERSAL}" == true ]]; then
    echo "==> Building universal release binary"
    ARM64_BUILD_PATH=".build/arm64-release"
    X86_64_BUILD_PATH=".build/x86_64-release"
    swift build -c release \
        --triple arm64-apple-macosx13.0 \
        --scratch-path "${ARM64_BUILD_PATH}"
    swift build -c release \
        --triple x86_64-apple-macosx13.0 \
        --scratch-path "${X86_64_BUILD_PATH}"
    ARM64_BIN_DIR="$(
        swift build -c release \
            --triple arm64-apple-macosx13.0 \
            --scratch-path "${ARM64_BUILD_PATH}" \
            --show-bin-path
    )"
    X86_64_BIN_DIR="$(
        swift build -c release \
            --triple x86_64-apple-macosx13.0 \
            --scratch-path "${X86_64_BUILD_PATH}" \
            --show-bin-path
    )"
    RELEASE_BIN="build/${APP_NAME}.universal"
    mkdir -p build
    lipo -create \
        "${ARM64_BIN_DIR}/${APP_NAME}" \
        "${X86_64_BIN_DIR}/${APP_NAME}" \
        -output "${RELEASE_BIN}"
else
    echo "==> Building release binary"
    swift build -c release
fi

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

if [[ "${ARCHIVE}" == true ]]; then
    ARCHIVE_PATH="build/${APP_NAME}.zip"
    CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
    echo "==> Creating ${ARCHIVE_PATH}"
    rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"
    (
        cd build
        shasum -a 256 "${APP_NAME}.zip" > "${APP_NAME}.zip.sha256"
    )
    echo "==> Created ${ARCHIVE_PATH} and ${CHECKSUM_PATH}"
fi

if [[ "${INSTALL}" == true ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"
    echo "==> Installed. Launch it:  open -a ${APP_NAME}"
else
    echo "==> Built ${APP_DIR}"
    echo "    Install with:  ./package.sh --install"
fi
