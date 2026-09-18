import Testing
import BamwareAccounts
@testable import BamwareAccountUI

/// Guideline 4.8: Google must never render without Apple beside it, and a
/// provider absent from `AccountModel.availableProviders` must never appear.
/// `AccountModel.availableProviders` already enforces this (bamware-ios#4);
/// these tests pin the same invariant at this package's own layer
/// (`SocialButtonsLayout.visibleProviders`), which is what `SignInScreen`
/// actually renders from.
@Suite struct SocialButtonsLayoutTests {
    @Test func bothAvailableShowsAppleThenGoogle() {
        let result = SocialButtonsLayout.visibleProviders(from: [.apple, .google])
        #expect(result == [.apple, .google])
    }

    @Test func reversedInputStillOrdersAppleFirst() {
        let result = SocialButtonsLayout.visibleProviders(from: [.google, .apple])
        #expect(result == [.apple, .google])
    }

    @Test func appleOnlyShowsOnlyApple() {
        let result = SocialButtonsLayout.visibleProviders(from: [.apple])
        #expect(result == [.apple])
    }

    @Test func googleOnlyWithoutAppleShowsNothing() {
        // Defense-in-depth: even if a caller hands this a hand-built array
        // that violates the "never Google alone" rule, the layout must not
        // render Google unaccompanied.
        let result = SocialButtonsLayout.visibleProviders(from: [.google])
        #expect(result.isEmpty)
    }

    @Test func emptyShowsNothing() {
        let result = SocialButtonsLayout.visibleProviders(from: [])
        #expect(result.isEmpty)
    }

    @Test func duplicateEntriesDoNotDuplicateButtons() {
        let result = SocialButtonsLayout.visibleProviders(from: [.apple, .apple, .google, .google])
        #expect(result == [.apple, .google])
    }
}
