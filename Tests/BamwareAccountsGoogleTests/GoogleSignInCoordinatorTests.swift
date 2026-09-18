import Testing
@testable import BamwareAccountsGoogle
import BamwareAccounts

/// `GoogleSignInCoordinator`'s no-SDK-touched path only — a real interactive
/// Google flow needs a presented window this environment can't provide
/// (see the type's doc comment). **Unverified beyond this.**
@Suite struct GoogleSignInCoordinatorTests {
    @Test func reportsProviderAsGoogle() {
        #expect(GoogleSignInCoordinator(clientID: nil).provider == .google)
    }

    @Test func missingClientIDIsUnavailableWithoutTouchingTheSDK() async {
        let outcome = await GoogleSignInCoordinator(clientID: nil).signIn()
        #expect(outcome == .unavailable(message: "Google sign-in isn't available yet. Please try another way to sign in."))
    }

    @Test func emptyClientIDIsAlsoUnavailable() async {
        let outcome = await GoogleSignInCoordinator(clientID: "").signIn()
        guard case .unavailable = outcome else {
            Issue.record("expected .unavailable, got \(outcome)")
            return
        }
    }
}
