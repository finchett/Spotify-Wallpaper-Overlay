# SpotifyWallpaper

Turn the macOS desktop into an ambient now-playing display. SpotifyWallpaper
sits above the wallpaper and below every app, following your music across every
Space without intercepting clicks.

![SpotifyWallpaper changing the desktop artwork and colors with the current track](assets/demo.webp)

## Features

- **Spotify Canvas or album artwork** — play a track's looping Canvas when one
  is available, or use an animated album-cover fallback with a slow Ken Burns
  effect.
- **Adaptive backgrounds** — build a gradient from the cover, keep your current
  wallpaper, or choose a separate image. Tune color intensity, blur, and
  brightness.
- **Every Space, no interaction cost** — the click-through overlay stays at the
  desktop level across macOS Spaces.
- **Custom song info** — show the title and artist briefly, permanently, or
  never; choose the corner, center position, and text size; or reveal it by
  clicking the desktop.
- **Playback-aware behavior** — animate the artwork away when Spotify stops and
  independently control the black menu-bar strip and rounded-corner masks.
- **Mission Control workaround** — optionally snapshot the composition into
  each Space's wallpaper during playback, then restore the original wallpaper
  when playback stops or the app quits.
- **Native Mac conveniences** — launch at login, with optional menu-bar and Dock
  icons.

Canvas is not available for every track. When it is missing or cannot be loaded,
SpotifyWallpaper falls back automatically to the animated cover treatment.

## Install

Requires macOS 13 or later and the Spotify desktop app.

```bash
curl -fsSL https://raw.githubusercontent.com/finchett/Spotify-Wallpaper-Overlay/main/install.sh | bash
open -a SpotifyWallpaper
```

The installer downloads the latest universal release to `~/Applications`,
verifies its published SHA-256 checksum, and replaces an older installation
safely. Run the same command again to update.

On first launch, allow the Automation requests for **System Events** and
**Spotify**. SpotifyWallpaper reads the current track from the local Spotify
app; no Spotify developer project or API key is required.

Releases are ad-hoc signed rather than Apple-notarized. The installer verifies
the checksum and clears the command-line download's quarantine attribute before
installation.

To install somewhere else:

```bash
curl -fsSL https://raw.githubusercontent.com/finchett/Spotify-Wallpaper-Overlay/main/install.sh \
  | SPOTIFY_WALLPAPER_INSTALL_DIR=/Applications bash
```

## Build from source

Install the Swift toolchain with `xcode-select --install` or full Xcode, then:

```bash
git clone https://github.com/finchett/Spotify-Wallpaper-Overlay.git
cd Spotify-Wallpaper-Overlay
swift run
```

For the packaged app:

```bash
./package.sh --install
open -a SpotifyWallpaper
```

To create the universal ZIP and checksum used by a release:

```bash
./package.sh --version 1.0.0 --universal --archive
```

The packaged bundle is recommended for the WebView login and stable Automation
permissions.

## How it works

| Component | Role |
|---|---|
| `AppDelegate.swift` | Menu bar, playback polling, and overlay coordination |
| `SpotifyClient.swift` | Current-track metadata from Spotify via AppleScript |
| `CanvasClient.swift` | Canvas lookup and automatic cover fallback |
| `OverlayController.swift` | One overlay window per display |
| `OverlayWindow.swift` | Click-through, all-Spaces desktop-level window |
| `OverlayContentView.swift` | Canvas, cover animation, song info, and desktop framing |
| `WallpaperBaker.swift` | Crash-recoverable Mission Control wallpaper workaround |
| `ColorExtractor.swift` | Cover-derived background color palette |

## Spotify Canvas note

Canvas is not a public Spotify API. The lookup uses an anonymous web token and
an internal protobuf endpoint, so Spotify can change or disable it without
notice. Failures are silent and always fall back to album artwork.

Overlay constants such as the menu-bar height and corner radius live at the top
of `OverlayContentView.swift`.
