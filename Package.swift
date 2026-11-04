// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SoundDock", platforms: [.macOS(.v13)], products: [.executable(name: "SoundDock", targets: ["SoundDock"])], targets: [.target(name: "AudioGuard", publicHeadersPath: "include"), .executableTarget(name: "SoundDock", dependencies: ["AudioGuard"]), .testTarget(name: "SoundDockTests", dependencies: ["SoundDock"])])
