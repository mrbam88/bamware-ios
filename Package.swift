// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BamwareIOS",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BamwareCore", targets: ["BamwareCore"]),
        .library(name: "BamwareUI", targets: ["BamwareUI"]),
        .library(name: "BamwareMessaging", targets: ["BamwareMessaging"])
    ],
    targets: [
        .target(name: "BamwareCore"),
        .target(name: "BamwareUI", dependencies: ["BamwareCore"]),
        .target(name: "BamwareMessaging", dependencies: ["BamwareCore", "BamwareUI"]),
        .testTarget(name: "BamwareCoreTests", dependencies: ["BamwareCore"]),
        .testTarget(name: "BamwareUITests", dependencies: ["BamwareUI"]),
        .testTarget(name: "BamwareMessagingTests", dependencies: ["BamwareMessaging"])
    ]
)
