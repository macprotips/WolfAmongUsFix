// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WolfFix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WolfFix", targets: ["WolfFix"]),
    ],
    targets: [
        // Finding the game and its bottle, installing and removing the fix. No UI, so it is easy to test.
        .target(name: "WolfFixKit"),
        // The SwiftUI app.
        .executableTarget(name: "WolfFix", dependencies: ["WolfFixKit"]),
        .testTarget(name: "WolfFixKitTests", dependencies: ["WolfFixKit"]),
    ]
)
