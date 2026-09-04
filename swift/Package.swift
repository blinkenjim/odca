// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ODCA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ODCAKit", targets: ["ODCAKit"]),
        .executable(name: "odca", targets: ["ODCA"]),
    ],
    targets: [
        .target(name: "ODCAKit"),
        .executableTarget(name: "ODCA", dependencies: ["ODCAKit"]),
        .testTarget(name: "ODCAKitTests", dependencies: ["ODCAKit"]),
    ]
)
