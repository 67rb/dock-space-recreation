// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Docklet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Docklet", targets: ["Docklet"])
    ],
    targets: [
        .executableTarget(name: "Docklet")
    ]
)
