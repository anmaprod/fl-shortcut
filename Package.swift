// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FLShortcut",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FLShortcut", path: "Sources/FLShortcut"),
        .testTarget(name: "FLShortcutTests", dependencies: ["FLShortcut"], path: "Tests/FLShortcutTests",
                    exclude: ["Fixtures"]),                 // sons d'essai lus par leur chemin (ClasseurSonsTests)
    ]
)
