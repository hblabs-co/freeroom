// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Freeroom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FreeroomCore", targets: ["FreeroomCore"]),
        .executable(name: "freeroom", targets: ["freeroom"]),
        .executable(name: "FreeroomApp", targets: ["FreeroomApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "FreeroomCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "freeroom",
            dependencies: [
                "FreeroomCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "FreeroomApp",
            dependencies: ["FreeroomCore"]
        ),
        .testTarget(
            name: "FreeroomCoreTests",
            dependencies: ["FreeroomCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
