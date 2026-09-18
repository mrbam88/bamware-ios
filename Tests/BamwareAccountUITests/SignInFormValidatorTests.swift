import Testing
@testable import BamwareAccountUI

@Suite struct SignInFormValidatorTests {
    @Test func signInRequiresValidEmailAndLongEnoughPassword() {
        #expect(SignInFormValidator.canSubmit(
            mode: .signIn, email: "a@b.com", password: "password1", name: ""
        ))
    }

    @Test func signInRejectsShortPassword() {
        #expect(!SignInFormValidator.canSubmit(
            mode: .signIn, email: "a@b.com", password: "short", name: ""
        ))
    }

    @Test func signInRejectsMalformedEmail() {
        #expect(!SignInFormValidator.canSubmit(
            mode: .signIn, email: "not-an-email", password: "password1", name: ""
        ))
    }

    @Test func signInIgnoresEmptyName() {
        // Name isn't collected in sign-in mode at all.
        #expect(SignInFormValidator.canSubmit(
            mode: .signIn, email: "a@b.com", password: "password1", name: ""
        ))
    }

    @Test func createAccountRequiresNonBlankName() {
        #expect(!SignInFormValidator.canSubmit(
            mode: .createAccount, email: "a@b.com", password: "password1", name: "   "
        ))
        #expect(SignInFormValidator.canSubmit(
            mode: .createAccount, email: "a@b.com", password: "password1", name: "Jamie"
        ))
    }
}
