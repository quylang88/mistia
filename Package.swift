// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MistiaCoreLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MistiaCoreLogic",
            targets: ["MistiaCoreLogic"]
        )
    ],
    targets: [
        .target(
            name: "MistiaCoreLogic",
            path: "Mistia/Shared/CoreLogic"
        ),
        .testTarget(
            name: "MistiaCoreLogicTests",
            dependencies: ["MistiaCoreLogic"]
        )
    ]
)
