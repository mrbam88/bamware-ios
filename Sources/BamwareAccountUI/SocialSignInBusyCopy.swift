import BamwareAccounts

/// Copy for the visible "Signing you in…" state during Apple/Google sign-in
/// (bamware-ios#12). Pure and unit-testable without rendering the view —
/// mirrors `AccountDeletionStepReducer`'s "transition rules live outside
/// SwiftUI" convention.
///
/// Typed, not routed through the string catalog: this composes a provider
/// name into the message the same way `AccountModel.friendlyMessage`
/// composes dynamic copy for the failed-sign-in banner, so it follows that
/// existing precedent rather than the static button labels' `Text(_:bundle:)`
/// pattern.
enum SocialSignInBusyCopy {
    static func message(for provider: SocialProvider?) -> String {
        switch provider {
        case .apple:
            "Signing in with Apple…"
        case .google:
            "Signing in with Google…"
        case nil:
            "Signing you in…"
        }
    }
}
