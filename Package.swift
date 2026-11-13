// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Glow", targets: ["Glow"]),
        .executable(name: "GlowChecks", targets: ["GlowChecks"]),
        .executable(name: "GlowInspect", targets: ["GlowInspect"]),
        .library(name: "GlowCore", targets: ["GlowCore"]),
        .library(name: "GlowHardware", targets: ["GlowHardware"])
    ],
    targets: [
        .target(name: "GlowCore"),
        .target(name: "GlowHardware"),
        .executableTarget(name: "Glow", dependencies: ["GlowCore", "GlowHardware"]),
        .executableTarget(name: "GlowChecks", dependencies: ["GlowCore"], path: "Checks/GlowChecks"),
        .executableTarget(name: "GlowInspect", dependencies: ["GlowHardware"])
    ],
    swiftLanguageModes: [.v5]
)
