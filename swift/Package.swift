// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ODCA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ODCAKit", targets: ["ODCAKit"]),
        .executable(name: "odca", targets: ["ODCAPlay"]),
        .executable(name: "odca-select", targets: ["ODCASelect"]),
    ],
    targets: [
        .target(name: "ODCAKit"),
        .target(name: "ODCAUI", dependencies: ["ODCAKit"]),  // window, rendering, keys: shared by both programs
        .executableTarget(name: "ODCAPlay", dependencies: ["ODCAKit", "ODCAUI"]),
        .executableTarget(name: "ODCASelect", dependencies: ["ODCAKit", "ODCAUI"]),
        .testTarget(name: "ODCAKitTests", dependencies: ["ODCAKit"]),
    ]
)
