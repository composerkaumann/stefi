// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SteFi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SteFi", targets: ["SteFi"])],
    targets: [
        .target(name: "StereoCore"),
        .executableTarget(name: "SteFi", dependencies: ["StereoCore"], path: "Sources/StereoCleanup"),
        .testTarget(name: "StereoCoreTests", dependencies: ["StereoCore"]),
        .testTarget(name: "SteFiTests", dependencies: ["SteFi", "StereoCore"])
    ]
)
