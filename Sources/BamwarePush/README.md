# BamwarePush

APNs registration + device client, shared by every Bamware app (bamware-ios#6,
ADR 0001). Depends on `BamwareAccounts` only (for the bearer token — see
below); `BamwareAccounts` does not depend back on this package.

Out of scope here (later tickets): notification content, deep links, the
push service itself (bamware-infra#8, D12 — **not built yet** as of this
package; the wire client is coded against that issue's documented contract),
BrewDesk wiring (D14).

## Configuration

Apps own tenant identity and the push-service host — nothing in this package
is a constant.

```swift
let pushConfig = PushConfig(
    baseURL: URL(string: "https://your-push-service-host")!,
    tenantId: "your-tenant-id"
)
```

## Public API

- **`PushRegistrar`** (actor) — the orchestrator. `requestPermissionAndRegister()`
  (permission, reusing BrewDesk's prompt policy, then
  `registerForRemoteNotifications()`), `didReceiveDeviceToken(_:)` (upload,
  called from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`),
  `deleteOnSignOut()`. Built entirely from injected protocols, so it never
  reaches into `UNUserNotificationCenter`, `UIApplication`, the network, or
  the keychain directly.

- **`PushPermissionRequesting`** — the permission seam.
  `SystemPushPermissionRequester()` (real, `UNUserNotificationCenter`-backed)
  and `FakePushPermissionRequester()` (deterministic, for tests/previews).

- **`RemoteNotificationRegistering`** — the one UIKit call this package
  needs. `UIKitRemoteNotificationRegistrar()` (real, iOS-only — see below)
  and `FakeRemoteNotificationRegistrar()` (records calls, no UIKit).

- **`PushDeviceRegistering`** — the wire seam for `POST /devices` /
  `DELETE /devices/:deviceId`. `PushDeviceAPI(config:)` (real, `URLSession`)
  and `FakePushDeviceClient()` (records calls, for tests).

- **`PushBearerProviding`** — the bearer-token seam. `SessionRefresher`
  (from `BamwareAccounts`, bamware-ios#3) conforms directly — its
  `validAccessToken()` already matches this protocol, so wiring it is just
  `SessionRefresher(...)` where a `PushBearerProviding` is expected.
  `AccountSessionStoreBearerProvider(sessions:)` is the fallback for an app
  that hasn't wired `SessionRefresher` (reads whatever token is currently
  stored, no proactive refresh). `FakePushBearerProvider()` for tests.

- **`PushSettings`** — per-type toggles (`isEnabled`/`setEnabled`),
  persisted in `UserDefaults`, defaulting every type to enabled until an app
  turns it off. `preferences()` is the map `PushRegistrar` sends as
  `preferences` on register.

- **`PushDeviceIdentity.current(defaults:)`** — a stable, `UserDefaults`-
  persisted per-install device id generator for `PushRegistrar.Configuration.deviceId`.

## Composition root wiring

```swift
import BamwareAccounts
import BamwarePush

let sessions = AccountSessionStore(persistence: KeychainSessionStore(service: config.keychainService))
let refresher = SessionRefresher(refreshing: AuthAPI(config: config), sessions: sessions)

let settings = PushSettings(knownTypes: ["matches", "messages", "digest"])

let registrar = PushRegistrar(
    configuration: .init(deviceId: PushDeviceIdentity.current()),
    permissions: SystemPushPermissionRequester(),
    remoteRegistrar: UIKitRemoteNotificationRegistrar(),
    deviceClient: PushDeviceAPI(config: pushConfig),
    bearer: refresher,
    settings: settings
)

// After the app's own permission moment (e.g. post-onboarding):
await registrar.requestPermissionAndRegister()

// AppDelegate / UIApplicationDelegateAdaptor:
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task { await registrar.didReceiveDeviceToken(deviceToken) }
}

// Before signing out — while the bearer is still valid:
await registrar.deleteOnSignOut()
model.signOut() // or AccountSessionStore.clear(), whichever the app uses
```

## Capability/entitlement checklist for a consuming app (Human-only)

- **Xcode capability:** Target → *Signing & Capabilities* → **+ Capability**
  → **Push Notifications**. Required for `registerForRemoteNotifications()`
  to produce a real APNs token — without it, the call fails silently at
  runtime even though everything compiles.
- **Background Modes → Remote notifications**, only if the app needs to
  react to a silent/background push (not required for foreground alert
  delivery).
- **APNs auth key** — provisioned once per Apple developer account,
  referenced by the push service's per-tenant SNS platform application
  (bamware-infra#7, tracked separately from this package and from D12).
  Nothing in `BamwarePush` holds or needs the key itself; it's server-side
  (bamware-infra#8) configuration.
- **bamware-push-service must exist and be reachable** at the `PushConfig.baseURL`
  passed in — bamware-infra#8 (D12) is not built yet as of this package, so
  `PushDeviceAPI` is untested against a live server (see spec-gap decisions
  below).

## Spec-gap decisions (bamware-ios#6)

- **`tenantId` in `PushConfig` is not sent on the wire.** bamware-infra#8's
  documented `POST /devices` body is `{deviceId, token, platform,
  preferences?}` — no `tenantId` field; the service derives tenant from the
  bearer's auth-middleware claim, matching the `bamware-dating-service`
  `deviceSchemas.ts` shape this ticket was told to read (also no
  `tenantId`). Kept `tenantId` on `PushConfig` anyway, unused, so the
  client's tenant identity is still a config value rather than a hardcoded
  constant — consistent with `AccountTenantConfig`'s own shape — and ready
  if a future contract needs it explicitly.
- **`DELETE /devices/:deviceId` treats 404 as success**, the same
  idempotent-delete convention `AuthAPI.deleteAccount` already uses in
  `BamwareAccounts` for `DELETE /auth/account`. bamware-infra#8's issue text
  doesn't say what a delete-of-an-already-gone-device returns; this is the
  closest in-repo precedent rather than a guess made from nothing, and it's
  the safer default (a sign-out flow that already failed to delete once
  shouldn't hard-fail a retry).
- **No token-change dedup.** `didReceiveDeviceToken` always re-uploads
  rather than comparing against a remembered "last uploaded token" — the
  ticket's "re-upload on token change" reads as "a changed token must
  reach the server," which unconditional upload already satisfies, and
  skip-if-unchanged adds state (a stored last-token) this ticket's five
  named deliverables don't ask for. If APNs delivers the identical token
  twice in a row, the second call is a harmless duplicate `POST /devices`
  (the service's own `RegisterDeviceRequestSchema`/repository shape looks
  upsert-like — "replace token" is explicitly one of bamware-infra#8's own
  test cases).
- **`deleteOnSignOut()` and the upload path both silently no-op when there
  is no bearer**, rather than throwing. `PushBearerProviding.validAccessToken()`
  throwing means "nothing to authenticate with" (never signed in, already
  signed out, or `SessionRefresherError.sessionEnded`), which for a
  best-effort background operation like a device-token upload or a
  sign-out cleanup call is not something the caller needs to react to —
  there's no unauthenticated fallback endpoint to retry against.
- **`PushRegistrar` is an `actor`, not `@MainActor`.** The BrewDesk pattern
  this ticket points at (`VisitReminderScheduling`) is `@MainActor` because
  BrewDeskKit's target defaults to `@MainActor` and every conformer is UI-
  driven. `BamwarePush` has no such target default and `PushRegistrar`'s
  own work (network calls, UserDefaults reads) isn't UI work; it's an actor
  purely so concurrent callers (e.g. a token-refresh callback racing a
  manual re-register call) serialize. `RemoteNotificationRegistering`'s
  real implementation still explicitly hops to `MainActor` for the one call
  that must run there (`UIApplication.registerForRemoteNotifications()`).
- **`registerForRemoteNotifications()`'s protocol requirement is a plain
  (non-`@MainActor`) `async` method**, not a `@MainActor`-isolated
  requirement, so `FakeRemoteNotificationRegistrar` (an `actor`, used in
  every test) can conform without an artificial MainActor hop, while
  `UIKitRemoteNotificationRegistrar`'s real implementation still satisfies
  it by hopping to `MainActor` internally via `MainActor.run`.
- **`AccountSessionStoreBearerProvider` (the "else the current access
  token" branch) does not attempt a refresh.** It reads
  `AccountSessionStore.session?.accessToken` directly — the point of this
  fallback is for an app that hasn't wired `SessionRefresher` at all, so
  there's no refresh capability to fall back to without also requiring
  `AuthAPI`/`AccountRefreshing` wiring, which would make it not actually a
  simpler fallback.
- **Untested against a live server.** bamware-infra#8 (the push service
  this package's `PushDeviceAPI` talks to) is not built yet, per the
  ticket's own framing ("D12 push service, NOT built yet"). `PushDeviceAPI`
  is coded against the issue's documented request/response contract and the
  `bamware-dating-service` schema shape, and is covered by `swift test`
  fakes only (`FakePushDeviceClient`) — no live-server or even a local mock
  HTTP server integration test exists. **Unverified beyond contract-shape
  compile-time and unit-test coverage.**
