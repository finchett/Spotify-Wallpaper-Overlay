// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyWallpaper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpotifyWallpaper",
            path: "Sources/SpotifyWallpaper"
        )
    ]
)
