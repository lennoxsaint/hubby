// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hubby",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hubby",
            path: "Sources/Hubby"
        ),
        .testTarget(
            name: "HubbyTests",
            dependencies: ["Hubby"],
            path: "Tests/HubbyTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
