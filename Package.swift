// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "RogueModInstaller", platforms: [.macOS(.v13)],
    products: [.executable(name: "RogueModInstaller", targets: ["RogueModInstaller"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "ModCore", dependencies: ["ZIPFoundation"], resources: [.process("Resources")]),
        .executableTarget(name: "RogueModInstaller", dependencies: ["ModCore"]),
        .testTarget(name: "ModCoreTests", dependencies: ["ModCore", "ZIPFoundation"]),
        .testTarget(name: "InstallerTests", dependencies: ["RogueModInstaller", "ModCore", "ZIPFoundation"])
    ])
