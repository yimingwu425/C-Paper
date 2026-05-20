// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CPaperNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CPaperNative", targets: ["CPaperNativeApp"])
    ],
    targets: [
        .executableTarget(
            name: "CPaperNativeApp",
            path: "Sources/CPaperNativeApp"
        ),
        .testTarget(
            name: "CPaperNativeTests",
            dependencies: ["CPaperNativeApp"],
            path: "Tests/CPaperNativeTests"
        )
    ]
)
