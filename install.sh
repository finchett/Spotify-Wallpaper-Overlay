#!/bin/bash
set -euo pipefail

APP_NAME="SpotifyWallpaper"
REPOSITORY="finchett/Spotify-Wallpaper-Overlay"
INSTALL_DIR="${SPOTIFY_WALLPAPER_INSTALL_DIR:-${HOME}/Applications}"
RELEASE_BASE="https://github.com/${REPOSITORY}/releases/latest/download"
ARCHIVE="${APP_NAME}.zip"
CHECKSUM="${ARCHIVE}.sha256"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "${APP_NAME} requires macOS." >&2
    exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spotify-wallpaper.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT

echo "Downloading the latest ${APP_NAME} release..."
curl --fail --location --silent --show-error \
    "${RELEASE_BASE}/${ARCHIVE}" \
    --output "${TEMP_DIR}/${ARCHIVE}"
curl --fail --location --silent --show-error \
    "${RELEASE_BASE}/${CHECKSUM}" \
    --output "${TEMP_DIR}/${CHECKSUM}"

echo "Verifying download..."
(
    cd "${TEMP_DIR}"
    shasum -a 256 --check "${CHECKSUM}"
    ditto -x -k "${ARCHIVE}" extracted
)

SOURCE_APP="${TEMP_DIR}/extracted/${APP_NAME}.app"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}.app"
BACKUP_APP="${TEMP_DIR}/${APP_NAME}.previous.app"

if [[ ! -d "${SOURCE_APP}" ]]; then
    echo "The release archive did not contain ${APP_NAME}.app." >&2
    exit 1
fi

mkdir -p "${INSTALL_DIR}"
pkill -x "${APP_NAME}" 2>/dev/null || true

if [[ -e "${TARGET_APP}" ]]; then
    mv "${TARGET_APP}" "${BACKUP_APP}"
fi

if ! ditto "${SOURCE_APP}" "${TARGET_APP}"; then
    if [[ -e "${BACKUP_APP}" ]]; then
        mv "${BACKUP_APP}" "${TARGET_APP}"
    fi
    echo "Installation failed; the previous app was restored." >&2
    exit 1
fi

# Releases are ad-hoc signed rather than notarized. Remove any quarantine
# attribute inherited by the command-line download so macOS can launch it.
xattr -dr com.apple.quarantine "${TARGET_APP}" 2>/dev/null || true

echo "Installed ${APP_NAME} to ${TARGET_APP}"
echo "Launch it with: open \"${TARGET_APP}\""
