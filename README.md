# SpotifyWallpaper

A macOS app that turns your desktop into an ambient "now playing" canvas. It runs
a transparent, click-through window pinned just above the wallpaper and below
every app window, so it shows through on **every Space** automatically. Whenever
the song changes it shows:

- the real **Spotify Canvas** looping video, when one is available, or
- a self-animated fallback: vibrant dominant-color gradient + centered album
  card with a slow Ken Burns zoom.

Plus your standard treatment: a black menu-bar bar and black rounded corners.

It's controlled from a small settings window (Spotify login, launch-at-login,
and an optional menu-bar icon).

An optional **Bake overlay during playback** setting snapshots the overlay
into the all-Spaces wallpaper once when playback starts or the track changes.
It restores the exact original wallpaper configuration when playback stops,
the setting is disabled, the app quits, or a previous run was interrupted.

An optional **Hide overlay when nothing is playing** setting runs the circular
reveal animation backwards when playback stops. The now-playing content retreats
while the black top strip and rounded corners remain; a nested option can hide
that black framing too.

An optional **Use vibrant colors** setting keeps the cover-derived hue but raises
the gradient's saturation and upper brightness for a more vivid background.

## Requirements

- macOS 13+
- Swift toolchain (`xcode-select --install` or full Xcode)
- The **Spotify desktop app** running (metadata is read from the local app)

## Build & run

```bash
cd SpotifyWallpaper
swift run
```

The settings window opens. Start playing something and the desktop updates
within a few seconds. First run prompts for Automation permission to control
**System Events** and **Spotify** — allow both. (The WebView login and reliable
permissions really want the packaged app below rather than `swift run`.)

## Install as an app (recommended)

Wrap the release build in a signed `.app` bundle and install it to `/Applications`:

```bash
./package.sh --install
open -a SpotifyWallpaper
```

Then, in the settings window, turn on **Launch at login** — it'll start
automatically on every boot (also visible in System Settings → General → Login
Items). The menu-bar icon is optional via the toggle beside it.

Packaging as a real bundle also makes the WebView login and Automation permissions
behave correctly, which they may not when run via bare `swift run`.

To update later, rerun `./package.sh --install` (quit the app first).

## Architecture

| File | Role |
|------|------|
| `AppDelegate.swift` | Menu bar, 3s polling, drives the overlay |
| `SpotifyClient.swift` | AppleScript → current track + static `artwork url` |
| `CanvasClient.swift` | **Unofficial** Spotify Canvas lookup (token + hand-rolled protobuf) |
| `OverlayController.swift` | One overlay window per screen |
| `OverlayWindow.swift` | Desktop-level, click-through, all-Spaces window |
| `OverlayContentView.swift` | Canvas video / animated cover, text, black bar + corners |
| `WallpaperBaker.swift` | Optional crash-recoverable all-Spaces wallpaper transaction |
| `ColorExtractor.swift` | Hue-bucketed vibrant color from the cover |

## Notes on Spotify Canvas

Canvas is **not** a public API. `CanvasClient` scrapes an anonymous web token
and POSTs a protobuf request to an internal endpoint. It can break whenever
Spotify changes things (they've added bot-protection to the token endpoint),
and many tracks simply have no Canvas. Any failure silently falls back to the
animated cover, so the app always shows *something*.

Overlay tuning lives at the top of `OverlayContentView.swift`
(`menuBarHeightPixels`, `cornerRadiusPixels`).
