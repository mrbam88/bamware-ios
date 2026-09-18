import SwiftUI
import BamwareAccounts
import BamwareUI

/// Signed-in account summary — name, email, sign out, plus the entry point
/// into `AccountDeletionScreen` (bamware-ios#5). Renders nothing meaningful
/// when signed out; the consuming app is expected to present `SignInScreen`
/// instead in that case (this package draws no navigation between the two —
/// that composition is the app's job).
public struct AccountScreen: View {
    private let model: AccountModel
    private let theme: any Theme

    @State private var isDeletionPresented = false

    public init(model: AccountModel, theme: any Theme) {
        self.model = model
        self.theme = theme
    }

    public var body: some View {
        Group {
            if let session = model.sessions.session {
                signedIn(session: session)
            } else {
                SmartText(String(localized: "Account", bundle: .module), theme: theme)
                    .accessibilityIdentifier("account-signed-out")
            }
        }
        .background(theme.backgroundColor)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isDeletionPresented) {
            NavigationStack {
                AccountDeletionScreen(model: model, theme: theme)
            }
        }
    }

    private func signedIn(session: AuthSession) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user.name)
                        .font(theme.font.weight(.semibold))
                    Text(session.user.email)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account-signed-in")
            }

            Section {
                Button {
                    model.signOut()
                } label: {
                    Text("Sign Out", bundle: .module)
                }
                .accessibilityIdentifier("account-sign-out")

                Button(role: .destructive) {
                    isDeletionPresented = true
                } label: {
                    Text("Delete Account", bundle: .module)
                }
                .accessibilityIdentifier("account-delete-entry")
            }
        }
    }
}
