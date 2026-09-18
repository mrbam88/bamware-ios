import Foundation

/// Everything `AccountModel.signIn(with:)` and `.availableProviders` need,
/// assembled once by the app's composition root and set on
/// `AccountModel.socialSignIn`.
public struct SocialSignInSupport: Sendable {
    /// Same tenant config the app used to build `AuthAPI`/`AccountModel` —
    /// `supportsApple`/`supportsGoogle` drive `availableProviders`, and
    /// `tenantId` is sent with every `socialSignIn` call.
    public let config: AccountTenantConfig
    /// Coordinators keyed by provider. Only the providers an app actually
    /// links appear here — an app with no `BamwareAccountsGoogle`
    /// dependency simply never puts a `.google` entry in this dictionary,
    /// and `availableProviders` hides it accordingly.
    public let coordinators: [SocialProvider: any SocialSignInCoordinating]
    /// The token-exchange seam — `AuthAPI` in production (see
    /// `AuthAPI+SocialSignIn.swift`).
    public let socialAuth: any SocialAuthServing

    public init(
        config: AccountTenantConfig,
        coordinators: [SocialProvider: any SocialSignInCoordinating],
        socialAuth: any SocialAuthServing
    ) {
        self.config = config
        self.coordinators = coordinators
        self.socialAuth = socialAuth
    }
}

/// Sign in with Apple / Google (bamware-ios#4). A NEW extension file —
/// `AccountModel.swift`'s existing password sign-in/up/out paths are out of
/// scope here and untouched.
extension AccountModel {
    /// Run the native flow for `provider` and, on success, exchange the
    /// resulting token for a Bamware session — mirrors
    /// `signIn(email:password:)`'s `working`/`idle`/`failed` phase
    /// handling, except a user-cancelled native sheet is a silent no-op
    /// (never `.failed`) — see `SocialSignInOutcome.cancelled`.
    ///
    /// A no-op (stays `.idle`, no network call) when `socialSignIn` hasn't
    /// been configured, or when `provider` has no coordinator — the same
    /// guard `availableProviders` uses to decide what to show, so a screen
    /// that only offers buttons for `availableProviders` can never hit
    /// this path, but calling it directly for an unlisted provider fails
    /// soft rather than crashing.
    public func signIn(with provider: SocialProvider) async {
        guard phase != .working else { return }
        guard let support = socialSignIn else {
            setPhaseForSocialSignIn(.failed(message: "Sign-in isn't set up yet."))
            return
        }
        guard let coordinator = support.coordinators[provider] else {
            setPhaseForSocialSignIn(.failed(message: "That sign-in option isn't available."))
            return
        }

        setPhaseForSocialSignIn(.working)
        let outcome = await coordinator.signIn()

        switch outcome {
        case .cancelled:
            // Silent no-op — never surfaced as an error (Baat RN convention,
            // `src/lib/socialAuth.ts`).
            setPhaseForSocialSignIn(.idle)

        case .unavailable(let message):
            setPhaseForSocialSignIn(.failed(message: message))

        case .credential(let credential):
            do {
                let session = try await support.socialAuth.socialSignIn(
                    provider: provider,
                    idToken: credential.idToken,
                    tenantId: support.config.tenantId,
                    name: credential.name
                )
                sessions.store(session)
                setPhaseForSocialSignIn(.idle)
            } catch {
                setPhaseForSocialSignIn(.failed(message: Self.socialFriendlyMessage(for: error)))
            }
        }
    }

    /// Providers this app can currently offer: the tenant supports it
    /// (`AccountTenantConfig.supportsApple`/`supportsGoogle`) AND a
    /// coordinator is actually linked for it. In `SocialProvider`
    /// declaration order (`.apple`, `.google`).
    ///
    /// Guideline 4.8 review is B8's job (the UI), but the model itself must
    /// never even report a config that would expose Google without Apple —
    /// so that invariant is enforced here, defensively, regardless of how
    /// `config`/`coordinators` got misconfigured upstream.
    public var availableProviders: [SocialProvider] {
        guard let support = socialSignIn else { return [] }
        var result: [SocialProvider] = []
        if support.config.supportsApple, support.coordinators[.apple] != nil {
            result.append(.apple)
        }
        if support.config.supportsGoogle, support.coordinators[.google] != nil {
            result.append(.google)
        }
        if result.contains(.google), !result.contains(.apple) {
            return []
        }
        return result
    }

    /// Friendly copy for `SocialAuthError`/network failures — parallel to
    /// `friendlyMessage(for:)` above, which doesn't know about
    /// `SocialAuthError` (it's `internal` there, defined in this ticket).
    fileprivate static func socialFriendlyMessage(for error: Error) -> String {
        if let socialError = error as? SocialAuthError, let description = socialError.errorDescription {
            return description
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            return "You look offline. Try again in a moment."
        }
        return "Couldn't reach the account service. Try again in a moment."
    }
}
