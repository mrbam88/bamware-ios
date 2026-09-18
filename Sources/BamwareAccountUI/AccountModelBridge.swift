import BamwareAccounts

// Swift 6 strict concurrency spec-gap (bamware-ios#5): `AccountModel`'s
// async methods (`signIn`, `signUp`, `signIn(with:)`, `deleteAccount`) are
// `nonisolated`, and `AccountModel` itself is neither `@MainActor` nor
// `Sendable` — deliberately, per `AccountModel.swift`'s own doc comment and
// the BamwareAccounts README ("can't be made Sendable/@MainActor without
// breaking AccountModelTests's synchronous access"). `AccountModel.swift`
// is out of this ticket's file fence, so that can't change here.
//
// Calling any of those methods from a SwiftUI `Button` action — which the
// compiler infers as MainActor-isolated purely from being written inside a
// View's `body` — trips the Swift 6 "sending risks data races" diagnostic
// on a PLAIN, unwrapped `Task { await model.signIn(...) }` even when
// `model` is used exactly once: the compiler tags `self.model` as
// belonging to the MainActor's isolation region the moment it's read
// inside `body`, and refuses to "send" that region-tagged reference into
// `signIn`'s nonisolated call, because a nonisolated async function is
// permitted to resume on a different executor than the one that called it.
// Verified with a minimal reproduction outside this package: the failure
// reproduces with a plain (non-`@Observable`) class too, with or without
// `Task { @MainActor in ... }`, and is unaffected by removing every other
// use of `model` in the same view — so it is not fixable by restructuring
// this package's own call sites.
//
// `AccountModel`'s actual mutable state (`phase`, `sessions`) is read and
// written only from this package's own MainActor call sites (SwiftUI
// button actions and the `@MainActor`-inferred view bodies that read
// `model.phase`/`model.isWorking` for rendering) — i.e. always from the
// main thread in practice, same as `AccountModelSocialSignInTests` and
// every other caller in this codebase. `UncheckedSendableBox` is a narrow,
// local `@unchecked Sendable` wrapper that opts a single `AccountModel`
// reference out of the compiler's over-conservative region check for
// exactly the span of one `Task { }` trigger, without pretending
// `AccountModel` itself is safe to use concurrently from multiple threads
// at once (it isn't, and nothing here does that).
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

extension AccountModel {
    /// Boxes `self` so a SwiftUI button action can hand it to `Task { }`
    /// without the Swift 6 "sending" false positive described above.
    var uncheckedSendableBox: UncheckedSendableBox<AccountModel> {
        UncheckedSendableBox(value: self)
    }
}
