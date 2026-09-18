import SwiftUI
import BamwareAccounts
import BamwareUI

// Themed Apple/Google buttons (bamware-ios#5, Guideline 4.8). Both render
// through this one view so they are guaranteed identical size and style —
// prominence can never drift between the two because there is only one
// button implementation.

/// Pure layout decision for which provider buttons a sign-in screen shows,
/// given whatever `AccountModel.availableProviders` currently reports.
///
/// `AccountModel.availableProviders` already enforces "never Google without
/// Apple" (bamware-ios#4) — this is a second, independent enforcement of the
/// same invariant at the UI layer, so `SignInScreen` never renders a bare
/// Google button even if some future caller hands it a hand-built array
/// instead of going through the model. Also pins the on-screen order to
/// Apple-then-Google regardless of the input order.
enum SocialButtonsLayout {
    static func visibleProviders(from providers: [SocialProvider]) -> [SocialProvider] {
        var result: [SocialProvider] = []
        if providers.contains(.apple) {
            result.append(.apple)
        }
        if providers.contains(.google), result.contains(.apple) {
            result.append(.google)
        }
        return result
    }
}

/// One provider's sign-in button. Every instance uses the same
/// `.borderedProminent` style tinted with `theme.primaryColor` — no literal
/// colors, and no per-provider style branch that could make one button more
/// prominent than the other.
struct SocialSignInButton: View {
    let provider: SocialProvider
    let theme: any Theme
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                label
            }
            .font(theme.font)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primaryColor)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var icon: some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
        case .google:
            // No first-party SF Symbol for the Google mark; a plain "G"
            // monogram keeps both buttons the same shape without pulling in
            // brand assets (out of scope here — BrewDesk integration is C9).
            Text(verbatim: "G")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
    }

    private var label: Text {
        switch provider {
        case .apple:
            Text("Continue with Apple", bundle: .module)
        case .google:
            Text("Continue with Google", bundle: .module)
        }
    }

    private var accessibilityIdentifier: String {
        switch provider {
        case .apple: "account-sign-in-apple"
        case .google: "account-sign-in-google"
        }
    }
}
