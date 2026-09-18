import SwiftUI
import BamwareUI

/// What the app receives when the onboarding step finishes. `skipped` is a
/// real, first-class outcome (bamware-ios#5) — not merely the absence of a
/// `continued` callback — so an app can tell "the user chose not to sign in
/// right now" apart from "this step never ran".
public enum AccountOnboardingOutcome: Sendable, Equatable {
    case continued
    case skipped
}

/// One optional onboarding page offering account sign-in, with a real Skip.
/// Copy (`title`/`body`) is supplied by the consuming app — it is product
/// value-prop text, not something this package can localize on the app's
/// behalf — while the Continue/Skip button labels come from this package's
/// own String Catalog.
public struct AccountOnboardingStep: View {
    private let theme: any Theme
    private let title: String
    private let bodyText: String
    private let symbolName: String?
    private let onOutcome: (AccountOnboardingOutcome) -> Void

    public init(
        theme: any Theme,
        title: String,
        body: String,
        symbolName: String? = nil,
        onOutcome: @escaping (AccountOnboardingOutcome) -> Void
    ) {
        self.theme = theme
        self.title = title
        self.bodyText = body
        self.symbolName = symbolName
        self.onOutcome = onOutcome
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(theme.primaryColor)
                    .accessibilityHidden(true)
            }

            SmartText(title, theme: theme)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding-account-title")

            Text(bodyText)
                .font(.body)
                .foregroundStyle(theme.secondaryColor)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding-account-body")

            Spacer()

            Button {
                onOutcome(.continued)
            } label: {
                Text("Continue", bundle: .module)
                    .font(theme.font)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
            .accessibilityIdentifier("onboarding-account-continue")

            Button {
                onOutcome(.skipped)
            } label: {
                Text("Skip", bundle: .module)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryColor)
            .accessibilityIdentifier("onboarding-account-skip")
        }
        .padding(24)
        .background(theme.backgroundColor)
    }
}
