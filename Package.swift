// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PauseCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PauseCore", targets: ["PauseCore"])],
    targets: [
        .target(name: "PauseCore", path: "Pause/Core"),
        .testTarget(name: "PauseCoreTests", dependencies: ["PauseCore"], path: "Tests/PauseCoreTests")
    ]
)
