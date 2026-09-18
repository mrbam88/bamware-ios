# BamwareAccountUI

Themed SwiftUI screens for `BamwareAccounts` (bamware-ios#5): sign in /
create account, account summary, account deletion, an optional onboarding
step, and privacy/terms links. Depends on `BamwareAccounts` + `BamwareUI`
only — never on `BamwareAccountsGoogle`, so linking this product never pulls
in the GoogleSignIn-iOS dependency; apps wire up Google's coordinator
themselves at their composition root (see `BamwareAccounts`' README) and
these screens just render whatever `AccountModel.availableProviders`
reports.

No screenshots — this environment can't run a simulator to capture any (see
"Unverified" below). Descriptions and the identifier list follow.

## Screens

### `SignInScreen(model:theme:)`

Sign in / create account. Apple and Google buttons render through the same
`SocialSignInButton` component (identical `.borderedProminent` style, tinted
with `theme.primaryColor`) so they are always equal size and prominence
(Guideline 4.8) — only their icon and label differ. Providers absent from
`model.availableProviders` are hidden entirely, and `SocialButtonsLayout
.visibleProviders` re-enforces "never Google without Apple" a second time at
this package's own layer, independent of `AccountModel`'s own enforcement.

Email is tucked behind a lower-emphasis "Continue with Email" button; tapping
it reveals email/password (+ name, in create-account mode) fields and a
submit button. A footer link toggles between sign-in and create-account
mode.

Identifiers: `account-sign-in-apple`, `account-sign-in-google`,
`account-sign-in-email`, plus (not spec-mandated, for consuming apps that
want them) `account-sign-in-header`, `account-sign-in-name-field`,
`account-sign-in-email-field`, `account-sign-in-password-field`,
`account-sign-in-submit`, `account-sign-in-mode-toggle`,
`account-sign-in-error`.

### `AccountScreen(model:theme:)`

Signed-in summary: name, email, Sign Out, and the entry point into
`AccountDeletionScreen` (presented as a sheet). Renders a minimal signed-out
placeholder if `model.sessions.session` is nil — this package draws no
navigation between `AccountScreen` and `SignInScreen`; that composition
belongs to the app.

Identifiers: `account-sign-out`, plus `account-signed-in`,
`account-signed-out`, `account-delete-entry` (not spec-mandated).

### `AccountDeletionScreen(model:theme:)`

Two-step deletion (explain → type-DELETE-to-confirm), driven by
`AccountModel.DeletionOutcome` via the pure `AccountDeletionStepReducer`:
`.completed`/`.authIncomplete` dismiss the screen (both leave the user
signed out either way — see `AccountModel.deleteAccount()`'s doc comment);
`.contentFailed(message:)` stays on the confirm step and shows the message
inline for a plain retry. The actual deletion order (content → auth record →
local session) lives entirely in `AccountModel.deleteAccount()`, out of this
package's scope.

Identifiers: `account-delete` (the actual "Delete My Account" trigger), plus
`account-delete-explain`, `account-delete-continue`, `account-delete-cancel`,
`account-delete-confirm-field`, `account-delete-error` (not spec-mandated).

### `AccountOnboardingStep(theme:title:body:symbolName:onOutcome:)`

One onboarding page: an app-supplied value-prop `title`/`body` (not
localized by this package — it's the app's own product copy) plus
Continue/Skip. `onOutcome` receives `AccountOnboardingOutcome.continued` or
`.skipped` — Skip is a real, distinguishable outcome the app receives, not
merely "nothing happened."

Identifiers: `onboarding-account-skip`, plus `onboarding-account-continue`,
`onboarding-account-title`, `onboarding-account-body` (not spec-mandated).

### `AccountPoliciesLinks(privacyURL:termsURL:theme:)`

"Privacy Policy" / "Terms of Use" links. URLs are config the app supplies
(not part of this package, same as `AccountTenantConfig`).

Identifiers (not spec-mandated): `account-policies-privacy`,
`account-policies-terms`.

## Full accessibility identifier list (spec-mandated)

| Identifier | Screen | Element |
|---|---|---|
| `account-sign-in-apple` | `SignInScreen` | Apple button |
| `account-sign-in-google` | `SignInScreen` | Google button |
| `account-sign-in-email` | `SignInScreen` | "Continue with Email" button |
| `account-sign-out` | `AccountScreen` | Sign Out button |
| `account-delete` | `AccountDeletionScreen` | "Delete My Account" button (final destructive trigger) |
| `onboarding-account-skip` | `AccountOnboardingStep` | Skip button |

## Localization

Every string this package owns (button labels, headers, footers, the
deletion flow's copy) ships in `Resources/Localizable.xcstrings`, en + es.
Value-prop copy passed into `AccountOnboardingStep` and URLs passed into
`AccountPoliciesLinks` are the app's own content and are rendered verbatim
(not looked up against this catalog) — localizing those is the app's job.

## Colors

Every screen renders exclusively through the `Theme` protocol
(`primaryColor`/`secondaryColor`/`backgroundColor`/`font`) — no literal
`Color` values anywhere in this package. `SmartText` (from `BamwareUI`) is
reused for themed headline text rather than a hand-rolled `Text` +
`.foregroundColor`. There's no dedicated "destructive"/"error" token on
`Theme`, so destructive actions use SwiftUI's semantic `role: .destructive`
(a system-provided affordance, not a chosen literal color) and inline error
copy uses `theme.secondaryColor` — see "Spec-gap decisions" below.

## Spec-gap decisions (bamware-ios#5)

- **No native `SignInWithAppleButton`/Google SDK button.** This package
  doesn't depend on `AuthenticationServices`'s branded control or
  `BamwareAccountsGoogle` (which would pull in the GoogleSignIn-iOS SDK just
  for a button). Both providers render through the same custom
  `SocialSignInButton` — same `.borderedProminent` style, same size, same
  padding — which is what makes "equal size and prominence" (Guideline 4.8)
  true by construction instead of by manual tuning. Google's icon is a
  plain "G" monogram (no official SF Symbol exists and pulling in brand
  assets is BrewDesk-integration/C9 territory, out of scope here).
- **Destructive actions use `role: .destructive`, not a themed color.** The
  `Theme` protocol (`BamwareUI`) has no error/danger color token, and adding
  one would mean editing `Theme.swift` — out of this ticket's file fence.
  `role: .destructive` is a system-provided semantic affordance (not a
  literal color this package chose), so it satisfies "zero literal colors"
  without needing a new theme token. Inline error/status copy (form
  validation, deletion failure messages) uses `theme.secondaryColor` for the
  same reason.
- **`AccountModelBridge.swift`'s `UncheckedSendableBox`.** `AccountModel`'s
  async methods are `nonisolated` and the type is intentionally neither
  `Sendable` nor `@MainActor` (see `AccountModel.swift`'s own doc comment —
  changing that would break `AccountModelTests`'s synchronous access, and
  `AccountModel.swift` is out of this ticket's file fence regardless). Under
  Swift 6 strict concurrency, any `View` conforming type implicitly carries
  `SwiftUI.View`'s `@MainActor` isolation onto **all** of its members (not
  just `body`), so even a single, single-use `Task { await
  model.signIn(...) }` written inside a button action fails to type-check
  with "sending risks data races" — reproduced in isolation outside this
  package with a minimal `@Observable` class, confirming it isn't fixable by
  restructuring this package's own call sites. `UncheckedSendableBox` is a
  narrow `@unchecked Sendable` wrapper, constructed synchronously (before
  crossing into `Task { }`) at each of the three call sites that trigger an
  `AccountModel` async method; `AccountModel`'s actual mutable state is read
  and written only from this package's own MainActor call sites in
  practice, same as every other caller in this codebase — nothing here
  introduces real concurrent access. See the file's doc comment for the
  full reasoning and the reproduction notes.
- **`AccountScreen`'s signed-out state is a placeholder, not a redirect to
  `SignInScreen`.** The ticket lists `SignInScreen` and `AccountScreen` as
  separate screens; wiring navigation between them is app composition-root
  territory (mirrors how `AccountPoliciesLinks`' URLs and
  `AccountOnboardingStep`'s copy are app-supplied), not something this
  package should assume every consuming app wants structured the same way.
- **Deletion screen bullet copy is generic, not per-app.** `AccountModel
  .deleteAccount()`'s content-deletion step is app-defined
  (`AccountContentDeleting`); this package has no visibility into what an
  app actually stores, so the three explain-step bullets describe only what
  `AccountModel` itself guarantees (account/sign-in removed, name/email
  removed from the auth service, local sign-out) rather than an
  app-specific content list.

## Unverified

- **No rendered/visual verification.** This is a pure SwiftUI library
  package with no host app; there's no simulator or XCUITest run in this
  environment. "Google never renders without Apple" and "providers absent
  from `availableProviders` are hidden" are covered by
  `SocialButtonsLayoutTests` (pure logic, six cases) rather than a
  rendering or snapshot test — the acceptance criterion is proven at the
  layout-decision layer that `SignInScreen` actually renders from, not by
  capturing pixels. Actual on-screen button sizing/equal-prominence,
  Dynamic Type behavior, and dark-mode contrast are unverified; consuming
  apps' own XCUITests (keyed off the identifier list above) are the
  intended verification point, same as `AccountModel`'s own
  Apple/Google-flow doc comments describe for `BamwareAccounts`.
- **No accessibility audit (VoiceOver, contrast) run.** Would need a hosted
  build (XCUIApplication accessibility audit APIs require a running app);
  out of reach here for the same reason as the rendering point above.
- Gate 3 (iOS simulator build) confirms the package compiles and links for
  `generic/platform=iOS Simulator`; it does not run or launch anything.
