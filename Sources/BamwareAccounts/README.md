# BamwareAccounts

Session storage and the account state machine (sign in / sign up / sign out,
ordered account deletion) shared by every Bamware app. Depends on
`BamwareCore` only. See ADR 0001 and
`bamware-ai/docs/bamware-account-platform.md` for the platform shape this
package is one piece of.

Out of scope here (later tickets): themed SwiftUI screens
(`BamwareAccountUI`, B8), push.

## Configuration

Apps own tenant identity — nothing in this package is a constant.

```swift
let config = AccountTenantConfig(
    tenantId: "your-tenant-id",
    authBaseURL: URL(string: "https://your-auth-host")!,
    keychainService: "com.yourcompany.yourapp.auth",
    supportsApple: true,
    supportsGoogle: true,
    googleClientID: "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com" // nil if not provisioned yet
)
```

`supportsApple`/`supportsGoogle` drive `AccountModel.availableProviders`
(bamware-ios#4); `googleClientID` is read only by `GoogleSignInCoordinator`
(`BamwareAccountsGoogle`).

## Public API

- **`AccountTenantConfig`** — tenant id, auth base URL, keychain service
  name, provider support flags. The only place tenant-specific values enter
  the package.

- **`AuthUser`**, **`AuthSession`**, **`AuthAPIError`** — wire model and typed
  errors for the auth service.

- **`AccountAuthServing`** — the auth-service seam: `register`, `signIn`,
  `deleteAccount`. Two implementations ship here:
  - **`AuthAPI(config:session:)`** — the live `URLSession` client.
  - **`AuthScenarioService(tenantId:seeded:)`** — a deterministic in-memory
    fake for UI tests and previews, with a seeded account
    (`AuthScenarioService.seededEmail` / `.seededPassword` / `.seededName`).

- **`AccountContentDeleting`** / **`NoUserContentService`** — the seam for an
  app's own server-side user-content deletion, run before the auth record is
  deleted (see ordered deletion below). Apps with no server-side user content
  can use `NoUserContentService` as-is.

- **`AuthSessionPersisting`** — session persistence seam, with
  **`KeychainSessionStore(service:)`** (real, keychain-backed) and
  **`InMemorySessionStore(session:)`** (ephemeral, for scenario launches and
  tests) implementations.

- **`AccountSessionStore(persistence:)`** — `@Observable` app-wide signed-in
  state. Apps own the instance and choose which persistence backend to
  inject; this package vends no singleton.

- **`SessionRefresher(refreshing:sessions:clock:)`** (actor) — silent
  refresh (bamware-ios#3). Refreshes the access token before it expires
  (< 2 min left) or on demand after a request 401s, single-flighting
  concurrent callers so they await one in-flight refresh instead of each
  presenting the same (single-use, rotating) refresh token to the server.
  See "Wiring silent refresh" below.

- **`AccountModel(auth:content:sessions:)`** — `@Observable` screen model.
  `signIn`/`signUp`/`signOut`, a `phase` (`idle`/`working`/`failed(message:)`)
  for UI to render, and `deleteAccount()` running the ordered deletion:
  content → auth record → local session. Both partial-failure paths are
  surfaced as `DeletionOutcome` (`.contentFailed` leaves the session intact
  for a plain retry; `.authIncomplete` clears the local session because the
  account is unusable either way). Also exposes
  `EnvironmentValues.accountAuthService` for screens that want to read an
  injected service from the SwiftUI environment.

- **`SocialProvider`** — `.apple` / `.google`.

- **`SocialSignInCoordinating`** — one provider's native sign-in flow seam.
  Two conformers: **`AppleSignInCoordinator()`** (this package, iOS-only —
  see below) and **`GoogleSignInCoordinator(clientID:)`** (the separate
  `BamwareAccountsGoogle` product). Both resolve to a
  `SocialSignInOutcome`: `.credential(SocialCredential)`, `.cancelled`
  (user dismissed the native sheet — never an error), or `.unavailable(message:)`.

- **`SocialAuthServing`** — the `POST /auth/social` seam. `AuthAPI` conforms
  via `socialSignIn(provider:idToken:tenantId:name:)`.

- **`AccountModel.socialSignIn: SocialSignInSupport?`** — set once by the
  app's composition root (below); backs `AccountModel.signIn(with:
  SocialProvider)` and `.availableProviders: [SocialProvider]`.

## Refresh contract (auth-service A2, bamware-auth-service#10)

`POST /auth/refresh` `{refreshToken}` → 200 the same
`{tokens: {accessToken, refreshToken}, user}` envelope as login/register,
**rotated**: a brand-new access + refresh pair, and the presented refresh
token is revoked (single use). Reusing an already-rotated-out refresh token
— or presenting any other invalid one — returns 401 (`refresh_reused` or
otherwise). `SessionRefresher` does not distinguish the specific 401 reason:
any 401 from `/auth/refresh` means the session is over.

## Wiring silent refresh into an app's own API client

```swift
let sessions = AccountSessionStore(persistence: KeychainSessionStore(service: config.keychainService))
let api = AuthAPI(config: config)
let refresher = SessionRefresher(refreshing: api, sessions: sessions)
let model = AccountModel(auth: api, sessions: sessions)
```

Before every request, ask for a token good for at least two minutes:

```swift
let token = try await refresher.validAccessToken()
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

If a request still comes back 401 (the access token was revoked
server-side ahead of its own `exp`), force one refresh and retry **once**:

```swift
let freshToken = try await refresher.refreshAfterUnauthorized()
// retry the same request with freshToken; a second 401 is your own
// client's job to treat as a failure — SessionRefresher does not loop.
```

Either call throws `SessionRefresherError.sessionEnded(reason:)` when the
server rejects the refresh token itself (expired, reused, revoked).
`SessionRefresher` has already cleared `AccountSessionStore` by the time
that throws; catch it wherever your client calls `validAccessToken()`/
`refreshAfterUnauthorized()` and hand the reason to `AccountModel` so UI
gets a "you were signed out" message instead of a generic error:

```swift
} catch SessionRefresherError.sessionEnded(let reason) {
    model.signOutOnSessionEnd(reason: reason)
    // surface model.phase (.failed(message:)) — e.g. route to sign-in.
}
```

`AccountSessionStore.accessExpiresAt` decodes the stored access token's
`exp` claim locally (base64url + `JSONDecoder`, no third-party JWT library,
no network call) — `SessionRefresher` uses it for the proactive check.

## Sign in with Apple / Google (bamware-ios#4)

### Composition root wiring

```swift
import BamwareAccounts
import BamwareAccountsGoogle // only if this app links the optional product

let auth = AuthAPI(config: config)
let model = AccountModel(auth: auth, sessions: sessions)

model.socialSignIn = SocialSignInSupport(
    config: config, // same AccountTenantConfig used above
    coordinators: [
        .apple: AppleSignInCoordinator(),
        .google: GoogleSignInCoordinator(clientID: config.googleClientID)
    ],
    socialAuth: auth // AuthAPI conforms to SocialAuthServing
)
```

An app that doesn't offer Google simply omits the `.google` entry (and the
`BamwareAccountsGoogle` import/dependency entirely) — `availableProviders`
hides it automatically, and `AuthAPI+SocialSignIn.swift`'s
`socialSignIn(...)` overload used above always uses `URLSession.shared`
under the hood (the instance's own injected `session` is private and
unreachable from this ticket's new files — see that file's doc comment for
why); apps that need to intercept it should call the `session:` overload on
the concrete `AuthAPI` instance directly.

### Linking the optional Google product (Human-only)

`BamwareAccountsGoogle` depends on `GoogleSignIn-iOS`, gated behind this
package's `GoogleSignIn` SwiftPM trait (off by default) so an app that
never links the product never resolves that dependency at all:

1. Add the `BamwareAccountsGoogle` product to the app target in Xcode's
   Package Dependencies UI (or the app's own `Package.swift`, if it
   consumes this package as a local/remote dependency).
2. Enable the `GoogleSignIn` trait for this package in the same UI (or pass
   `.package(..., traits: ["GoogleSignIn"])` from the consuming manifest) —
   otherwise `GoogleSignInCoordinator.signIn()` compiles but always reports
   `.unavailable` (see that type's doc comment).

### Human-only setup the consuming app must add

- **Xcode capability:** Target → *Signing & Capabilities* → **+ Capability**
  → **Sign in with Apple**. Required for `AppleSignInCoordinator` — without
  it, `ASAuthorizationController` fails at runtime even though everything
  compiles.
- **Info.plist (Google only):**
  - A **URL Type** whose **URL Scheme** is the *reversed client ID* (the
    `REVERSED_CLIENT_ID` from the app's `GoogleService-Info.plist`/Google
    Cloud console entry, e.g.
    `com.googleusercontent.apps.1234567890-abcdefg`). Required for the
    Google sign-in sheet to return control to the app.
  - Optionally a top-level `GIDClientID` string key with the same client id
    passed to `AccountTenantConfig.googleClientID` — not required by this
    package (the client id is always passed explicitly via
    `GoogleSignInCoordinator(clientID:)`), but some Google-side flows
    (`restorePreviousSignIn`) expect it; add it for consistency with
    Google's own setup guide.

## Spec-gap decisions (bamware-ios#2)

Ported from the first app-embedded implementation this ticket lifted out of,
minus the pieces that were specific to that app rather than part of the five
named files in this ticket's scope:

- Dropped the service-resolver helper and the app-launch-environment-driven
  convenience initializers (`AccountSessionStore(environment:)`,
  `AuthScenarioService.shared`, `AccountSessionStore.shared`). That
  launch-environment type is the source app's own `-UITestScenario`
  launch-argument parser — an app/UI composition-root concern, not one of the
  five named files, and this ticket puts UI/screens out of scope (B8). Apps
  now choose and construct `AuthAPI` vs. `AuthScenarioService`, and
  `KeychainSessionStore` vs. `InMemorySessionStore`, explicitly at their own
  composition root.
- Removed `AuthAPI.defaultBaseURL` and its `#if DEBUG` localhost branch per
  the ticket's explicit instruction — the app always passes the URL via
  `AccountTenantConfig`.
- Removed the hardcoded tenant-id constant the source app used; `tenantId`
  comes from `AccountTenantConfig` everywhere it used to be a constant.
- Dropped the source app's tenant-id-pin test (it pinned a constant that no
  longer exists here); added `AccountTenantConfigTests` and config-injection
  cases in `AuthAPITests`/`AuthScenarioServiceTests` in its place.

## Spec-gap decisions (bamware-ios#3, silent refresh)

- **No `AccountAuthServing.refresh` method.** `AuthContract.swift` (where
  `AccountAuthServing` lives) is out of this ticket's file fence — another
  agent owns B7 (Apple/Google sign-in) against the same file in parallel.
  Refresh gets its own narrow seam, `AccountRefreshing`, in
  `SessionRefresher.swift`; `AuthAPI` conforms to both protocols.
- **`SessionRefresher` does not hold a reference to `AccountModel`.** The
  ticket text reads as `SessionRefresher` pushing the signed-out transition
  into `AccountModel` directly. That would require a stored
  `AccountModel`/`AccountSessionEnding` delegate on an actor, which needs
  `Sendable` — and `AccountModel` can't be made `Sendable` (or `@MainActor`)
  without breaking `AccountModelTests.swift`'s existing synchronous,
  non-`await` access to `model.phase`, a file outside this ticket's fence
  that's shared with the deletion-flow ticket. Instead `SessionRefresher`
  throws a typed `SessionRefresherError.sessionEnded(reason:)` (after
  already clearing `AccountSessionStore`), and `AccountModel` gains one new
  method, `signOutOnSessionEnd(reason:)`, that the app's own call site
  invokes from its `catch`. Same net behavior — a revoke ends up as
  `model.phase == .failed(message:)` — reached by a thrown-error return path
  instead of a stored actor→class delegate, which keeps every existing file
  and test outside this ticket's fence untouched. Documented above under
  "Wiring silent refresh".
- **`AccountSessionStore` gained internal locking and `@unchecked Sendable`.**
  `SessionRefresher` (an actor) calls `sessions.store`/`sessions.clear` from
  a different isolation domain than whatever reads `sessions.session` for
  UI. `session` is now `NSLock`-guarded and manually instrumented for
  `Observable` tracking (`access`/`withMutation`) so UI still updates live;
  the public API (`session`, `isSignedIn`, `store`, `clear`) is unchanged.
- **`accessExpiresAt` is computed, not stored.** Decoded from the current
  session's access-token `exp` claim on read, so it can never drift out of
  sync with `session` and needs no extra persistence.
- **Any 401 from `/auth/refresh` is treated uniformly** as "session ended"
  (`SessionEndReason.refreshRejected`) without inspecting the response body
  for `refresh_reused` specifically, per the ticket's explicit instruction
  ("treat any 401 from refresh as 'session ended'") and the A2 contract not
  requiring clients to distinguish the reason.
- **auth-service#10 (the A2 server contract) has no PR yet** — `gh pr list
  -R mrbam88/bamware-auth-service --search refresh` and `--state all` turned
  up nothing beyond the merged A1 tenant-registry PR. This client is built
  against the issue's contract description only; the wire test
  (`AuthAPITests.refreshSendsRefreshTokenBodyAndDecodesRotatedSession`) pins
  the envelope shape login/register already use, which is the safest
  assumption but unverified against a live/merged server implementation.

## Spec-gap decisions (bamware-ios#4)

- **`AccountModel` needed two small, direct edits, not just a new-file
  extension.** A `final class`'s stored state and a `private(set)` setter
  can't be added from another file — Swift `private`/stored-property rules
  are file/type-scoped. So `AccountModel.swift` itself gained exactly two
  things: the `public var socialSignIn: SocialSignInSupport?` property and
  an internal `setPhaseForSocialSignIn(_:)` helper so
  `AccountModel+SocialSignIn.swift` can drive `phase` without a public
  setter. Everything else — the type, `signIn(with:)`,
  `availableProviders` — lives in the new file. `AccountModel.swift`'s
  existing password paths are otherwise untouched.
- **`AuthAPI.socialSignIn` takes `tenantId`/`session` as explicit
  parameters**, unlike `register`/`signIn`. `AuthAPI.swift` is out of scope
  for this ticket (bamware-ios#3 owns it) and its `tenantId`/`session`
  storage is `private` — file-scoped, so a same-type extension in a
  different file has no access to it. The protocol-satisfying overload
  defaults `session` to `.shared`; a second overload takes an explicit
  `session:` for callers (tests, or a composition root) that want the same
  interceptable session used elsewhere.
- **`BamwareAccountsGoogle` is gated behind a new `GoogleSignIn` SwiftPM
  trait (SE-0450), off by default** — bumping `swift-tools-version` from
  6.0 to 6.1. Plain unconditional dependency declaration was tried first
  and rejected: SwiftPM resolves/fetches a package-level dependency for the
  *whole* manifest graph on any invocation, regardless of `--target`, so
  `swift build --target BamwareAccounts` fetched the entire GoogleSignIn-iOS
  tree even though nothing in that target imports it. With the trait off by
  default, that fetch simply doesn't happen for `swift build --target
  BamwareAccounts` or a plain `swift test`. The tradeoff: trait activation
  is also whole-graph, not per-target, so `swift build --target
  BamwareAccountsGoogle` *by itself* (no flags) only builds the stub below
  — exercising the real SDK requires `swift build --target
  BamwareAccountsGoogle --traits GoogleSignIn` explicitly. Quoted in the
  PR description.
- **`GoogleSignInCoordinator` degrades to a stub when the trait isn't
  active**, via `#if canImport(GoogleSignIn)`: `signIn()` always reports
  `.unavailable` and no Google symbol is referenced. This is what lets
  `BamwareAccountsGoogle` and `BamwareAccountsGoogleTests` build and pass
  under a plain, unscoped `swift test` (default traits) without ever
  linking the SDK — the alternative (making the target itself
  conditionally excluded from the package) isn't something SwiftPM
  supports for test targets.
- **`AppleSignInCoordinator` sends an Apple-recommended nonce
  (SHA256-hashed, random) even though bamware-auth-service doesn't verify
  the identity token's `nonce` claim yet** (`socialAuthService.ts`'s
  `verifySocialIdToken` checks `iss`/`aud`/`sub`/`email` only). This is the
  client-side half of Apple's replay-protection pattern regardless, so
  server-side verification can be added later with no client change.
- **Neither coordinator's interactive flow could be exercised for real in
  this environment** — no signed device/simulator run, no presented
  window. Both are covered by mocked-coordinator tests
  (`AccountModelSocialSignInTests`) for the behavior contract (cancel,
  unavailable, credential → token exchange, name/email handling); the
  actual `ASAuthorizationController`/`GIDSignIn` integration is
  compile-verified only (the Apple coordinator via a supplementary
  iOS-simulator `swiftc -typecheck` pass since the required gates run on
  the macOS host and never compile its `#if os(iOS)` body; the Google
  coordinator via gate 3's real `--traits GoogleSignIn` build, which does
  compile against the real SDK). **Unverified beyond that.**
