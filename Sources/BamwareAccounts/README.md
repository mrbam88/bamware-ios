# BamwareAccounts

Session storage and the account state machine (sign in / sign up / sign out,
ordered account deletion) shared by every Bamware app. Depends on
`BamwareCore` only. See ADR 0001 and
`bamware-ai/docs/bamware-account-platform.md` for the platform shape this
package is one piece of.

Out of scope here (later tickets): Apple/Google sign-in (B7), themed SwiftUI
screens (`BamwareAccountUI`, B8), push.

## Configuration

Apps own tenant identity — nothing in this package is a constant.

```swift
let config = AccountTenantConfig(
    tenantId: "your-tenant-id",
    authBaseURL: URL(string: "https://your-auth-host")!,
    keychainService: "com.yourcompany.yourapp.auth",
    supportsApple: true,
    supportsGoogle: true
)
```

`supportsApple`/`supportsGoogle` are carried for future UI (B7/B8); this
package's session and account logic does not read them.

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
