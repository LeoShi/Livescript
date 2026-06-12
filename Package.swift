// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Livescript",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LivescriptCore",
            path: "Livescript/Domain"
        ),
        .testTarget(
            name: "LivescriptCoreTests",
            dependencies: ["LivescriptCore"],
            path: "Tests/LivescriptCoreTests"
        )
    ]
)
