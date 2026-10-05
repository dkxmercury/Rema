// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RemaCore", targets: ["RemaCore"]),
    ],
    targets: [
        .target(name: "RemaCore"),
        .testTarget(name: "RemaCoreTests", dependencies: ["RemaCore"]),
    ]
)
