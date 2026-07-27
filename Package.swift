// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShowClock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShowClock",
            path: "Sources/ShowClock"
        )
    ]
)
