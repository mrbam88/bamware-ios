import Testing
import BamwareAccounts
@testable import BamwareAccountUI

@Suite struct AccountDeletionStepReducerTests {
    @Test func completedDismissesWithNoError() {
        let result = AccountDeletionStepReducer.apply(outcome: .completed)
        #expect(result.shouldDismiss)
        #expect(result.errorMessage == nil)
    }

    @Test func authIncompleteAlsoDismisses() {
        // Local session is cleared either way (see AccountModel.deleteAccount
        // doc comment) — the confirm screen has nothing left to do.
        let result = AccountDeletionStepReducer.apply(outcome: .authIncomplete)
        #expect(result.shouldDismiss)
        #expect(result.errorMessage == nil)
    }

    @Test func contentFailedStaysOnScreenWithMessage() {
        let result = AccountDeletionStepReducer.apply(
            outcome: .contentFailed(message: "Couldn't delete your account right now. Check your connection and try again.")
        )
        #expect(!result.shouldDismiss)
        #expect(result.errorMessage == "Couldn't delete your account right now. Check your connection and try again.")
        #expect(result.step == .confirm)
    }
}
