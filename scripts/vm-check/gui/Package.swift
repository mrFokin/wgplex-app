// swift-tools-version: 6.0
import PackageDescription

// GUI harness: compiles the REAL app sources (Sources/Wgplex/*.swift except main.swift,
// symlinked by run-gui.sh) with its own main that drives the real StatusController /
// WindowController in-process and renders the window to PNG. Runs INSIDE the check VM.
let package = Package(
    name: "gui",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WgplexKit"),
        .executableTarget(name: "WgplexGUI", dependencies: ["WgplexKit"]),
    ],
    swiftLanguageModes: [.v6]
)
