// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "ContextSynapse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "contextsynapse", targets: ["contextsynapse"]),
        .executable(name: "ContextSynapseApp", targets: ["ContextSynapseApp"]),
        .library(name: "SynapseCore", targets: ["SynapseCore"])
    ],
    targets: [
        .target(name: "SynapseCore", path: "Sources/SynapseCore"),
        .executableTarget(name: "contextsynapse", dependencies: ["SynapseCore"], path: "Sources/contextsynapse"),
        .executableTarget(name: "ContextSynapseApp", dependencies: ["SynapseCore"], path: "Sources/ContextSynapseApp")
    ]
)
