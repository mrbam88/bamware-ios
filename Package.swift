// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BamwareIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BamwareCore", targets: ["BamwareCore"]),
        .library(name: "BamwareUI", targets: ["BamwareUI"]),
        .library(name: "BamwareMessaging", targets: ["BamwareMessaging"]),
        .library(name: "BamwareAccounts", targets: ["BamwareAccounts"])
    ],
    targets: [
        .target(name: "BamwareCore"),
        .target(name: "BamwareUI", dependencies: ["BamwareCore"]),
        .target(name: "BamwareMessaging", dependencies: ["BamwareCore", "BamwareUI"]),
        .target(name: "BamwareAccounts", dependencies: ["BamwareCore"]),
        .testTarget(name: "BamwareCoreTests", dependencies: ["BamwareCore"]),
        .testTarget(name: "BamwareUITests", dependencies: ["BamwareUI"]),
        .testTarget(name: "BamwareMessagingTests", dependencies: ["BamwareMessaging"]),
        .testTarget(name: "BamwareAccountsTests", dependencies: ["BamwareAccounts"])
    ]
)
