// swift-tools-version: 6.0
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
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.0.0"
        )
    ],
    targets: [
        .target(
            name: "NebCore",
            dependencies: [
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "NebCoreTests",
            dependencies: ["NebCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
