import SwiftUI
import BamwareUI

/// Privacy/terms links (bamware-ios#5) — URLs are config the app supplies
/// (tenant-specific, like `AccountTenantConfig`); this package owns only the
/// "Privacy Policy"/"Terms of Use" copy and the themed presentation.
public struct AccountPoliciesLinks: View {
    private let privacyURL: URL
    private let termsURL: URL
    private let theme: any Theme

    public init(privacyURL: URL, termsURL: URL, theme: any Theme) {
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 16) {
            Link(destination: privacyURL) {
                Text("Privacy Policy", bundle: .module)
            }
            .accessibilityIdentifier("account-policies-privacy")

            Link(destination: termsURL) {
                Text("Terms of Use", bundle: .module)
            }
            .accessibilityIdentifier("account-policies-terms")
        }
        .font(.footnote)
        .foregroundStyle(theme.secondaryColor)
    }
}
