// swift-tools-version:5.9
// The app's logic that doesn't need a window: the shelf on disk, capture
// detection, the daily sweep, pixelation and notch geometry. The app target
// (see ../project.yml) imports this as a local package; `swift test` here runs
// the tests without Xcode.
import PackageDescription

let package = Package(
    name: "ShelfCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShelfCore", targets: ["ShelfCore"]),
    ],
    targets: [
        .target(name: "ShelfCore"),
        .testTarget(name: "ShelfCoreTests", dependencies: ["ShelfCore"]),
    ]
)
