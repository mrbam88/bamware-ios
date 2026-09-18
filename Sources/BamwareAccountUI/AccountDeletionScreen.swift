import SwiftUI
import BamwareAccounts
import BamwareUI

/// Ordered account deletion (bamware-ios#5). The actual ordering — content →
/// auth record → local session — lives in `AccountModel.deleteAccount()`
/// (pinned by `AccountModelTests` in `BamwareAccounts`); this screen only
/// renders the three `AccountModel.DeletionOutcome` cases it can come back
/// with, via `AccountDeletionStepReducer`.
public struct AccountDeletionScreen: View {
    @Environment(\.dismiss) private var dismiss

    /// Typed, not localized — deliberate friction, matching the pattern
    /// this ticket's copy was ported from (BrewDesk's `AccountDeletionScreen`).
    static let confirmWord = "DELETE"

    private let model: AccountModel
    private let theme: any Theme

    @State private var step: AccountDeletionStep = .explain
    @State private var confirmText = ""
    @State private var errorMessage: String?

    public init(model: AccountModel, theme: any Theme) {
        self.model = model
        self.theme = theme
    }

    public var body: some View {
        List {
            switch step {
            case .explain: explainSection
            case .confirm: confirmSection
            }
        }
        .background(theme.backgroundColor)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Step 1: explain

    private var explainSection: some View {
        Group {
            Section {
                Label {
                    Text("This cannot be undone", bundle: .module)
                        .font(theme.font.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Your account and sign-in")
                    bullet("Your name and email are removed from our servers")
                    bullet("You'll be signed out on this device")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account-delete-explain")

            Section {
                Button(role: .destructive) {
                    step = .confirm
                } label: {
                    Text("Continue to Delete", bundle: .module)
                }
                .accessibilityIdentifier("account-delete-continue")

                Button {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .accessibilityIdentifier("account-delete-cancel")
            }
        }
    }

    // MARK: - Step 2: type-to-confirm

    private var confirmed: Bool {
        confirmText.trimmingCharacters(in: .whitespaces) == Self.confirmWord
    }

    private var confirmSection: some View {
        Group {
            Section {
                TextField(text: $confirmText) {
                    Text("Type \(Self.confirmWord) to confirm", bundle: .module)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .accessibilityIdentifier("account-delete-confirm-field")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryColor)
                        .accessibilityIdentifier("account-delete-error")
                }

                Button(role: .destructive) {
                    let box = model.uncheckedSendableBox
                    Task { await performDeletion(box) }
                } label: {
                    if model.isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Delete My Account", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!confirmed || model.isWorking)
                .accessibilityIdentifier("account-delete")
            } footer: {
                Text("Deleting removes your account permanently.", bundle: .module)
            }

            Section {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .accessibilityIdentifier("account-delete-cancel")
            }
        }
    }

    /// Takes a pre-boxed `model` — see `AccountModelBridge.swift` for why a
    /// plain `Task { await model.deleteAccount() }` written inside this
    /// `View`'s `body` doesn't type-check under Swift 6 strict concurrency.
    private func performDeletion(_ model: UncheckedSendableBox<AccountModel>) async {
        guard !model.value.isWorking else { return }
        errorMessage = nil
        let outcome = await model.value.deleteAccount()
        let result = AccountDeletionStepReducer.apply(outcome: outcome)
        step = result.step
        errorMessage = result.errorMessage
        if result.shouldDismiss {
            dismiss()
        }
    }

    private func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(theme.secondaryColor)
            Text(key, bundle: .module)
        }
        .font(.subheadline)
    }
}

/// Which of the two deletion steps is on screen.
enum AccountDeletionStep: Equatable, Sendable {
    case explain
    case confirm
}

/// Maps an `AccountModel.DeletionOutcome` to what the confirm step should do
/// next — pure and unit-testable without rendering the view (mirrors
/// `AccountModel`'s own "transition rules live outside SwiftUI" convention).
enum AccountDeletionStepReducer {
    struct Result: Equatable {
        let step: AccountDeletionStep
        let errorMessage: String?
        let shouldDismiss: Bool
    }

    static func apply(outcome: AccountModel.DeletionOutcome) -> Result {
        switch outcome {
        case .completed, .authIncomplete:
            // Signed out either way — `.authIncomplete` is retryable
            // end-to-end after a fresh sign-in (both endpoints treat
            // "already gone" as success), so there's nothing more for this
            // screen to do but leave.
            return Result(step: .confirm, errorMessage: nil, shouldDismiss: true)
        case .contentFailed(let message):
            return Result(step: .confirm, errorMessage: message, shouldDismiss: false)
        }
    }
}
