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
        // StrictConcurrency surfaces latent actor-isolation issues ahead of the
        // v0.4 SynapticCircuit wiring without bumping swift-tools-version.
        .target(name: "SynapseCore", path: "Sources/SynapseCore",
                swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .executableTarget(name: "contextsynapse", dependencies: ["SynapseCore"], path: "Sources/contextsynapse"),
        .executableTarget(name: "ContextSynapseApp", dependencies: ["SynapseCore"], path: "Sources/ContextSynapseApp"),
        .testTarget(name: "BayesianConvergenceTests", dependencies: ["SynapseCore"], path: "Tests")
    ]
)
