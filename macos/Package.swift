// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CatsShared",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CatsShared", targets: ["CatsShared"])],
    targets: [
        .target(name: "CatsShared", path: "Shared"),
        .testTarget(
            name: "CatsSharedTests", dependencies: ["CatsShared"], path: "Tests",
            resources: [.copy("Fixtures")]),
    ]
)
