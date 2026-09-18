# BamwareAccounts

Session storage and the account state machine (sign in / sign up / sign out,
ordered account deletion) shared by every Bamware app. Depends on
`BamwareCore` only. See ADR 0001 and
`bamware-ai/docs/bamware-account-platform.md` for the platform shape this
package is one piece of.

Out of scope here (later tickets): silent token refresh (B6), Apple/Google
sign-in (B7), themed SwiftUI screens (`BamwareAccountUI`, B8), push.

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

- **`AccountModel(auth:content:sessions:)`** — `@Observable` screen model.
  `signIn`/`signUp`/`signOut`, a `phase` (`idle`/`working`/`failed(message:)`)
  for UI to render, and `deleteAccount()` running the ordered deletion:
  content → auth record → local session. Both partial-failure paths are
  surfaced as `DeletionOutcome` (`.contentFailed` leaves the session intact
  for a plain retry; `.authIncomplete` clears the local session because the
  account is unusable either way). Also exposes
  `EnvironmentValues.accountAuthService` for screens that want to read an
  injected service from the SwiftUI environment.

## Spec-gap decisions (bamware-ios#2)

Ported from BrewDesk's first implementation, minus the pieces that were
BrewDesk-app-specific rather than part of the five named files in this
ticket's scope:

- Dropped `AccountServiceResolver` and the `LaunchEnvironment`-driven
  convenience initializers (`AccountSessionStore(environment:)`,
  `AuthScenarioService.shared`, `AccountSessionStore.shared`).
  `LaunchEnvironment` is BrewDesk's own `-UITestScenario` launch-argument
  parser — an app/UI composition-root concern, not one of the five named
  files, and this ticket puts UI/screens out of scope (B8). Apps now choose
  and construct `AuthAPI` vs. `AuthScenarioService`, and
  `KeychainSessionStore` vs. `InMemorySessionStore`, explicitly at their own
  composition root.
- Removed `AuthAPI.defaultBaseURL` and its `#if DEBUG` localhost branch per
  the ticket's explicit instruction — the app always passes the URL via
  `AccountTenantConfig`.
- Removed the `BrewDeskTenant` enum; `tenantId` comes from
  `AccountTenantConfig` everywhere it used to be a constant.
- Dropped the `brewDeskTenantIdNeverDrifts` test (pinned a constant that no
  longer exists); added `AccountTenantConfigTests` and config-injection cases
  in `AuthAPITests`/`AuthScenarioServiceTests` in its place.
