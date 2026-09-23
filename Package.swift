// swift-tools-version:5.8
import PackageDescription

var products: [Product] = [
    .executable(name: "contextsynapse", targets: ["contextsynapse"]),
    .library(name: "SynapseCore", targets: ["SynapseCore"])
]

var targets: [Target] = [
    .target(name: "SynapseCore", path: "Sources/SynapseCore"),
    .executableTarget(name: "contextsynapse", dependencies: ["SynapseCore"], path: "Sources/contextsynapse"),
    .testTarget(name: "BayesianConvergenceTests", dependencies: ["SynapseCore"], path: "Tests")
]

#if os(macOS)
products.append(.executable(name: "ContextSynapseApp", targets: ["ContextSynapseApp"]))
targets.append(.executableTarget(name: "ContextSynapseApp", dependencies: ["SynapseCore"], path: "Sources/ContextSynapseApp"))
#endif

let package = Package(
    name: "ContextSynapse",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
