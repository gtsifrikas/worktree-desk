// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorktreeDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WorktreeDesk", targets: ["WorktreeDesk"])
    ],
    targets: [
        .executableTarget(
            name: "WorktreeDesk"
        )
    ]
)
