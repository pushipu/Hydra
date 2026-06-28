// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hydra",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DownloadCore", targets: ["DownloadCore"]),
        .executable(name: "hydractl", targets: ["hydractl"]),
        .executable(name: "hydra-host", targets: ["hydra-host"]),
        .executable(name: "HydraApp", targets: ["HydraApp"]),
    ],
    targets: [
        .target(name: "DownloadCore"),
        .executableTarget(name: "hydractl", dependencies: ["DownloadCore"]),
        .executableTarget(name: "hydra-host", dependencies: ["DownloadCore"]),
        .executableTarget(name: "HydraApp", dependencies: ["DownloadCore"]),
        .testTarget(name: "DownloadCoreTests", dependencies: ["DownloadCore"]),
    ]
)
