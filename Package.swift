// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FLShortcut",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FLShortcut", path: "Sources/FLShortcut")
    ]
)
