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
- **Smooth Spaces and Mission Control** — optionally keep the current
  composition visible while switching desktops.
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

Run the same install command again whenever you want to update.

## Getting started

1. Open SpotifyWallpaper and allow the Automation requests for **System Events**
   and **Spotify**.
2. Start playing something in Spotify.
3. Open SpotifyWallpaper's settings from the menu-bar icon to customize the
   artwork, background, song info, playback behavior, and launch-at-login.

That's it—SpotifyWallpaper runs quietly in the background and follows the local
Spotify app. No Spotify developer project or API key is required.
