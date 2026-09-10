// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ODCA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ODCAKit", targets: ["ODCAKit"]),
        .executable(name: "odca", targets: ["ODCAPlay"]),
        .executable(name: "odca-select", targets: ["ODCASelect"]),
        .executable(name: "odca-evolve", targets: ["ODCAEvolve"]),
    ],
    targets: [
        .target(name: "CShow"),  // the play script parser, generated C (script/regen)
        .target(name: "ODCAKit", dependencies: ["CShow"]),
        .target(name: "ODCAUI", dependencies: ["ODCAKit"]),  // window, rendering, keys: shared by both programs
        .executableTarget(name: "ODCAPlay", dependencies: ["ODCAKit", "ODCAUI"]),
        .executableTarget(name: "ODCASelect", dependencies: ["ODCAKit", "ODCAUI"]),
        .executableTarget(name: "ODCAEvolve", dependencies: ["ODCAKit"]),  // no window: the kit alone
        .testTarget(name: "ODCAKitTests", dependencies: ["ODCAKit"]),
    ]
)
