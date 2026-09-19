import Testing
import BamwareAccounts
@testable import BamwareAccountUI

/// The busy-overlay copy shown during the server round trip of Apple/Google
/// sign-in (bamware-ios#12).
@Suite struct SocialSignInBusyCopyTests {
    @Test func appleProviderGetsAppleSpecificMessage() {
        #expect(SocialSignInBusyCopy.message(for: .apple) == "Signing in with Apple…")
    }

    @Test func googleProviderGetsGoogleSpecificMessage() {
        #expect(SocialSignInBusyCopy.message(for: .google) == "Signing in with Google…")
    }

    @Test func noProviderFallsBackToGenericMessage() {
        #expect(SocialSignInBusyCopy.message(for: nil) == "Signing you in…")
    }
}
