// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NebCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "NebCore", targets: ["NebCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/matrix-org/matrix-rust-components-swift",
            from: "26.5.13"
        )
    ],
    targets: [
        .target(
            name: "NebCore",
            dependencies: [
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")
            ]
        ),
        .testTarget(
            name: "NebCoreTests",
            dependencies: ["NebCore"]
        )
    ]
)
