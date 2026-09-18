import SwiftUI
import BamwareAccounts
import BamwareUI

/// Sign in / create account (bamware-ios#5). Apple and Google render at
/// equal size and prominence (Guideline 4.8, `SocialSignInButton`); email is
/// tucked behind a lower-emphasis "Continue with email" button so social
/// stays the default path when it's available. Providers absent from
/// `model.availableProviders` are hidden entirely — see
/// `SocialButtonsLayout.visibleProviders`.
public struct SignInScreen: View {
    private let model: AccountModel
    private let theme: any Theme

    @State private var mode: SignInMode = .signIn
    @State private var isEmailFormExpanded = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""

    public init(model: AccountModel, theme: any Theme) {
        self.model = model
        self.theme = theme
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                let providers = SocialButtonsLayout.visibleProviders(from: model.availableProviders)
                if !providers.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(providers, id: \.self) { provider in
                            SocialSignInButton(
                                provider: provider,
                                theme: theme,
                                isDisabled: model.isWorking
                            ) {
                                let box = model.uncheckedSendableBox
                                Task { await box.value.signIn(with: provider) }
                            }
                        }
                    }
                }

                if !isEmailFormExpanded {
                    Button {
                        isEmailFormExpanded = true
                    } label: {
                        Text("Continue with Email", bundle: .module)
                            .font(theme.font)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.secondaryColor)
                    .accessibilityIdentifier("account-sign-in-email")
                } else {
                    emailForm
                }

                modeToggle

                if case .failed(let message) = model.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryColor)
                        .accessibilityIdentifier("account-sign-in-error")
                }
            }
            .padding(24)
        }
        .background(theme.backgroundColor)
    }

    private var header: some View {
        // `SmartText` renders through `theme.primaryColor`/`theme.font` —
        // the package's one themed-text component, reused here rather than
        // a hand-rolled `Text` + `.foregroundColor` (which is exactly the
        // literal-color pattern the house rules forbid).
        SmartText(
            mode == .signIn
                ? String(localized: "Welcome back", bundle: .module)
                : String(localized: "Create your account", bundle: .module),
            theme: theme
        )
        .accessibilityIdentifier("account-sign-in-header")
    }

    @ViewBuilder
    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mode == .createAccount {
                TextField(text: $name) {
                    Text("Name", bundle: .module)
                }
                #if os(iOS)
                .textContentType(.name)
                #endif
                .accessibilityIdentifier("account-sign-in-name-field")
            }

            TextField(text: $email) {
                Text("Email", bundle: .module)
            }
            #if os(iOS)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .accessibilityIdentifier("account-sign-in-email-field")

            SecureField(text: $password) {
                Text("Password (at least 8 characters)", bundle: .module)
            }
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("account-sign-in-password-field")

            Button {
                let box = model.uncheckedSendableBox
                Task { await submit(box) }
            } label: {
                if model.isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(mode == .signIn ? "Sign In" : "Create Account", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
            .disabled(!canSubmit || model.isWorking)
            .accessibilityIdentifier("account-sign-in-submit")
        }
    }

    private var modeToggle: some View {
        Button {
            mode = mode == .signIn ? .createAccount : .signIn
        } label: {
            Text(
                mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in",
                bundle: .module
            )
            .font(.footnote)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondaryColor)
        .accessibilityIdentifier("account-sign-in-mode-toggle")
    }

    private var canSubmit: Bool {
        SignInFormValidator.canSubmit(mode: mode, email: email, password: password, name: name)
    }

    /// Takes a pre-boxed `model` (constructed synchronously in the button
    /// action, before crossing into `Task { }`) rather than reading
    /// `self.model` in here directly — see `AccountModelBridge.swift` for
    /// why a plain `Task { await model.signIn(...) }` written inside a
    /// `View`'s `body` doesn't type-check under Swift 6 strict concurrency.
    private func submit(_ model: UncheckedSendableBox<AccountModel>) async {
        switch mode {
        case .signIn:
            await model.value.signIn(email: email, password: password)
        case .createAccount:
            await model.value.signUp(email: email, password: password, name: name.trimmingCharacters(in: .whitespaces))
        }
        if model.value.sessions.isSignedIn {
            password = ""
        }
    }
}

/// Sign-in vs. create-account mode for `SignInScreen`'s email form.
enum SignInMode: String, CaseIterable, Sendable {
    case signIn
    case createAccount
}

/// Pure client-side validation for the email/password/name form —
/// unit-testable without a rendered view (mirrors `AccountModel`'s own
/// "transition rules live outside SwiftUI" convention).
enum SignInFormValidator {
    static func canSubmit(mode: SignInMode, email: String, password: String, name: String) -> Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 8
        let nameOK = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passwordOK && nameOK
    }
}
