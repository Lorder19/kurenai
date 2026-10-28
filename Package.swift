// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kurenai",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kurenai",
            path: "Sources/Kurenai",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        ),
        .testTarget(name: "KurenaiTests", dependencies: ["Kurenai"], path: "Tests/KurenaiTests")
    ]
)
