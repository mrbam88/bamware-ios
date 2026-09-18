import BamwareAccounts
import Foundation

#if canImport(GoogleSignIn)
import GoogleSignIn
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#endif

/// Google sign-in via the `GoogleSignIn-iOS` SDK, pinned to an exact
/// version in `Package.swift` behind the `GoogleSignIn` package trait
/// (bamware-ios#4).
///
/// Lives in this SEPARATE `BamwareAccountsGoogle` product/target — not
/// `BamwareAccounts` — so an app that never offers Google sign-in doesn't
/// link the SDK at all.
///
/// SwiftPM resolves a trait-gated dependency for the WHOLE package graph,
/// not per requested `--target` — so a plain `swift build`/`swift test`
/// (default traits, `GoogleSignIn` off) must never need the real SDK, even
/// when building/testing this very target. That's why the body below is
/// split on `#if canImport(GoogleSignIn)`: with the trait enabled
/// (`--traits GoogleSignIn`), `GIDSignIn` actually drives the flow; without
/// it, `signIn()` degrades to `.unavailable` and no Google symbol is
/// referenced at all. The public API — `provider`, `init(clientID:)`,
/// `signIn()` — is identical either way, so callers and tests don't branch
/// on trait state. See the PR description for the exact gate invocations
/// this requires.
///
/// A real interactive Google flow needs a presented window this package's
/// own `swift test` can't drive — **unverified in this environment beyond
/// compile-time checks.**
public final class GoogleSignInCoordinator: SocialSignInCoordinating, @unchecked Sendable {
    public let provider: SocialProvider = .google

    /// `AccountTenantConfig.googleClientID` — `nil` when this tenant hasn't
    /// provisioned Google yet, in which case `signIn()` reports
    /// `.unavailable` without touching the SDK at all.
    private let clientID: String?

    public init(clientID: String?) {
        self.clientID = clientID
    }

    @MainActor
    public func signIn() async -> SocialSignInOutcome {
        guard let clientID, !clientID.isEmpty else {
            return .unavailable(message: "Google sign-in isn't available yet. Please try another way to sign in.")
        }

        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        #if os(iOS)
        guard let presenter = Self.topViewController() else {
            return .unavailable(message: "Couldn't start Google sign-in. Try again.")
        }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                continuation.resume(returning: Self.outcome(result: result, error: error))
            }
        }
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            return .unavailable(message: "Couldn't start Google sign-in. Try again.")
        }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: window) { result, error in
                continuation.resume(returning: Self.outcome(result: result, error: error))
            }
        }
        #else
        return .unavailable(message: "Google sign-in isn't available on this platform.")
        #endif

        #else
        // The `GoogleSignIn` package trait isn't enabled for this build
        // (see the type doc) — no SDK to call. An app that actually wants
        // Google sign-in builds with `--traits GoogleSignIn`; this branch
        // only exists so the rest of the package (and this target's own
        // tests) stay green without it.
        return .unavailable(message: "Google sign-in isn't available in this build.")
        #endif
    }

    #if canImport(GoogleSignIn)
    // MARK: - Result mapping

    private static func outcome(result: GIDSignInResult?, error: Error?) -> SocialSignInOutcome {
        if let error {
            let nsError = error as NSError
            // `NS_ERROR_ENUM(kGIDSignInErrorDomain, GIDSignInErrorCode)`
            // bridges to Swift as `GIDSignInError`/`GIDSignInError.Code`;
            // compare via the raw domain/code to stay correct regardless of
            // exactly how that bridging names things.
            if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.Code.canceled.rawValue {
                return .cancelled
            }
            return .unavailable(message: "Google sign-in failed. Try again.")
        }
        guard let idToken = result?.user.idToken?.tokenString else {
            return .unavailable(message: "Google didn't return a usable credential. Try again.")
        }
        return .credential(SocialCredential(idToken: idToken, name: result?.user.profile?.name))
    }

    #if os(iOS)
    @MainActor
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
    #endif
    #endif
}
