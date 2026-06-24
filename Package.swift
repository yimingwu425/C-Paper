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
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.4"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.10.3")
    ],
    targets: [
        .executableTarget(
            name: "CPaperNativeApp",
            dependencies: [
                "SwiftSoup",
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "macos/Sources/CPaperNativeApp"
        ),
        .testTarget(
            name: "CPaperNativeTests",
            dependencies: [
                "CPaperNativeApp",
                .product(name: "ViewInspector", package: "ViewInspector")
            ],
            path: "macos/Tests/CPaperNativeTests"
        )
    ]
)
