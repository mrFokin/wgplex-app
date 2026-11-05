// swift-tools-version: 5.9
import PackageDescription

// Integration smoke of WgplexKit against a live wgplex daemon. Runs INSIDE the
// check VM (see ../run-all.sh). Not part of the app package. The app package
// exposes no library product, so Sources/WgplexKit is a symlink to the real
// sources (created by run-all.sh).
let package = Package(
    name: "smoke",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WgplexKit"),
        .executableTarget(name: "smoke", dependencies: ["WgplexKit"]),
    ]
)
