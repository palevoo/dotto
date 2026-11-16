// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "design",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .executableTarget(name: "dot", dependencies: [.product(name: "Core", package: "Core")]),
    ]
)
