// swift-tools-version: 6.1
// Bumped from 6.0 (bamware-ios#4) — Package Traits (SE-0450), used below,
// need tools-version 6.1+. No other manifest behavior changes with this bump.
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
        .library(name: "BamwareAccounts", targets: ["BamwareAccounts"]),
        // Optional product (bamware-ios#4): only an app that links this
        // (and enables the `GoogleSignIn` trait below) pulls in the
        // GoogleSignIn-iOS dependency. `BamwareAccounts` itself never
        // depends on it.
        .library(name: "BamwareAccountsGoogle", targets: ["BamwareAccountsGoogle"]),
        // BamwarePush (bamware-ios#6): APNs registration + device client.
        .library(name: "BamwarePush", targets: ["BamwarePush"]),
        // Themed account screens (bamware-ios#5). Depends inward on
        // BamwareAccounts + BamwareUI only — never on BamwareAccountsGoogle,
        // so this product never pulls in the GoogleSignIn-iOS dependency
        // either; apps wire up Google's coordinator themselves at their
        // composition root (see BamwareAccounts' README) and this package
        // just renders whatever `AccountModel.availableProviders` reports.
        .library(name: "BamwareAccountUI", targets: ["BamwareAccountUI"])
    ],
    // OFF by default (bamware-ios#4) — deliberately not a default trait.
    // SwiftPM resolves/fetches a trait-gated dependency for the whole
    // package graph as soon as the trait is active for a given invocation,
    // regardless of which `--target` was requested. Keeping `GoogleSignIn`
    // off by default is what makes `swift build --target BamwareAccounts`
    // and a plain `swift test` never touch GoogleSignIn-iOS; an app (or a
    // build of `BamwareAccountsGoogle` that wants the real SDK, not the
    // `.unavailable` stub — see that target's doc comment) passes
    // `--traits GoogleSignIn` explicitly. Quoted gate invocations in the PR.
    traits: [
        "GoogleSignIn"
    ],
    dependencies: [
        // Pinned exact version (bamware-ios#4).
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "9.2.0")
    ],
    targets: [
        .target(name: "BamwareCore"),
        .target(name: "BamwareUI", dependencies: ["BamwareCore"]),
        .target(name: "BamwareMessaging", dependencies: ["BamwareCore", "BamwareUI"]),
        .target(name: "BamwareAccounts", dependencies: ["BamwareCore"]),
        .target(
            name: "BamwareAccountsGoogle",
            dependencies: [
                "BamwareAccounts",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS", condition: .when(traits: ["GoogleSignIn"]))
            ]
        ),
        .testTarget(name: "BamwareCoreTests", dependencies: ["BamwareCore"]),
        .testTarget(name: "BamwareUITests", dependencies: ["BamwareUI"]),
        .testTarget(name: "BamwareMessagingTests", dependencies: ["BamwareMessaging"]),
        .testTarget(name: "BamwareAccountsTests", dependencies: ["BamwareAccounts"]),
        .testTarget(name: "BamwareAccountsGoogleTests", dependencies: ["BamwareAccountsGoogle"]),
        // BamwarePush (bamware-ios#6): APNs registration + device client.
        // Depends on BamwareAccounts only (bearer token via
        // PushBearerProviding/SessionRefresher) — dependencies point inward.
        .target(name: "BamwarePush", dependencies: ["BamwareAccounts"]),
        .testTarget(name: "BamwarePushTests", dependencies: ["BamwarePush"]),
        .target(
            name: "BamwareAccountUI",
            dependencies: ["BamwareAccounts", "BamwareUI"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BamwareAccountUITests", dependencies: ["BamwareAccountUI"])
    ]
)
