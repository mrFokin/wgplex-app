// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wgplex",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WgplexKit"),
        .executableTarget(name: "Wgplex", dependencies: ["WgplexKit"]),
        .testTarget(name: "WgplexKitTests", dependencies: ["WgplexKit"]),
    ],
    swiftLanguageModes: [.v6]
)
