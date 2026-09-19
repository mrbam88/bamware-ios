import Foundation
import Testing
@testable import BamwareAccounts

/// `AccountModel.signIn(with:)` / `.availableProviders` (bamware-ios#4),
/// with mocked coordinators and a mocked `SocialAuthServing` — a real
/// Apple/Google flow can't run in this environment (see
/// `AppleSignInCoordinator`/`GoogleSignInCoordinator` doc comments).
@Suite struct AccountModelSocialSignInTests {
    private static let tenantId = "test-tenant"

    private struct MockCoordinator: SocialSignInCoordinating {
        let provider: SocialProvider
        let outcome: SocialSignInOutcome
        func signIn() async -> SocialSignInOutcome { outcome }
    }

    /// `@unchecked Sendable` box so a test can read `model.socialStep` from
    /// inside a `SocialSignInCoordinating`/`SocialAuthServing` conformer's
    /// `async` method (bamware-ios#12) — same trick as
    /// `BamwareAccountUI`'s `UncheckedSendableBox`, reproduced locally
    /// since that type isn't exported from this package. Safe here for the
    /// same reason it's safe there: everything in this test runs on one
    /// thread, there's no concurrent access to `model`.
    private struct TestBox<Value>: @unchecked Sendable {
        let value: Value
    }

    /// Records `model.socialStep` at the moment `signIn()` runs, so a test
    /// can pin `AccountModel.signIn(with:)` sets `.waitingForProvider`
    /// *before* handing off to the coordinator (bamware-ios#12).
    private struct StepCapturingCoordinator: SocialSignInCoordinating {
        let provider: SocialProvider
        let outcome: SocialSignInOutcome
        let modelBox: TestBox<AccountModel>
        let recorder: Recorder<AccountModel.SocialStep?>
        func signIn() async -> SocialSignInOutcome {
            recorder.append(modelBox.value.socialStep)
            return outcome
        }
    }

    /// Same idea as `StepCapturingCoordinator`, for the token-exchange leg
    /// (`.exchangingToken`) — records `model.socialStep` at the moment
    /// `socialSignIn` runs.
    private struct StepCapturingSocialAuth: SocialAuthServing {
        let modelBox: TestBox<AccountModel>
        let recorder: Recorder<AccountModel.SocialStep?>
        let result: Result<AuthSession, Error>
        func socialSignIn(
            provider: SocialProvider, idToken: String, tenantId: String, name: String?
        ) async throws -> AuthSession {
            recorder.append(modelBox.value.socialStep)
            return try result.get()
        }
    }

    private struct MockSocialAuth: SocialAuthServing {
        var result: Result<AuthSession, Error> = .failure(SocialAuthError.invalidResponse)
        /// Records the exact args this seam was called with, for the
        /// first-sign-in name/email assertions.
        let recordedCall: Recorder<Call>?

        struct Call: Sendable {
            let provider: SocialProvider
            let idToken: String
            let tenantId: String
            let name: String?
        }

        func socialSignIn(
            provider: SocialProvider, idToken: String, tenantId: String, name: String?
        ) async throws -> AuthSession {
            recordedCall?.append(Call(provider: provider, idToken: idToken, tenantId: tenantId, name: name))
            return try result.get()
        }
    }

    /// Minimal thread-safe recorder — `nonisolated` so it can be called
    /// from any isolation domain a coordinator/service happens to run on.
    private final class Recorder<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [T] = []
        func append(_ entry: T) { lock.withLock { entries.append(entry) } }
        var all: [T] { lock.withLock { entries } }
    }

    private func makeModel(
        config: AccountTenantConfig,
        coordinators: [SocialProvider: any SocialSignInCoordinating],
        socialAuth: any SocialAuthServing
    ) -> AccountModel {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)
        model.socialSignIn = SocialSignInSupport(config: config, coordinators: coordinators, socialAuth: socialAuth)
        return model
    }

    private struct NeverCalledAuth: AccountAuthServing {
        func register(email: String, password: String, name: String) async throws -> AuthSession {
            fatalError("password path not under test here")
        }
        func signIn(email: String, password: String) async throws -> AuthSession {
            fatalError("password path not under test here")
        }
        func deleteAccount(accessToken: String) async throws {}
    }

    private static func session(name: String) -> AuthSession {
        AuthSession(
            accessToken: "access-1", refreshToken: "refresh-1",
            user: AuthUser(userId: "u1", email: "tester@bamware.com", name: name, tenantId: tenantId)
        )
    }

    // MARK: - Cancel → no error state

    @Test func cancelledSignInLeavesPhaseIdleAndSessionSignedOut() async {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)
        model.socialSignIn = SocialSignInSupport(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true
            ),
            coordinators: [.apple: MockCoordinator(provider: .apple, outcome: .cancelled)],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        await model.signIn(with: .apple)

        #expect(model.phase == .idle) // no error state on cancel
        #expect(!sessions.isSignedIn)
    }

    // MARK: - Unavailable provider

    @Test func unavailableCoordinatorOutcomeSurfacesItsOwnMessage() async {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsGoogle: true
            ),
            coordinators: [.google: MockCoordinator(
                provider: .google, outcome: .unavailable(message: "Google sign-in isn't available yet.")
            )],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        await model.signIn(with: .google)

        #expect(model.phase == .failed(message: "Google sign-in isn't available yet."))
    }

    @Test func signInWithProviderThatHasNoCoordinatorFailsSoftWithoutCrashing() async {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!, keychainService: "svc"
            ),
            coordinators: [:],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        await model.signIn(with: .apple)

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }

    // MARK: - availableProviders — hides unavailable, Apple never absent when Google present

    @Test func availableProvidersHidesProviderTenantDoesNotSupport() {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true, supportsGoogle: false
            ),
            coordinators: [
                .apple: MockCoordinator(provider: .apple, outcome: .cancelled),
                .google: MockCoordinator(provider: .google, outcome: .cancelled),
            ],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        #expect(model.availableProviders == [.apple])
    }

    @Test func availableProvidersHidesProviderWithNoLinkedCoordinator() {
        // Tenant supports Google, but the app never linked
        // BamwareAccountsGoogle (no .google entry in coordinators).
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true, supportsGoogle: true
            ),
            coordinators: [.apple: MockCoordinator(provider: .apple, outcome: .cancelled)],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        #expect(model.availableProviders == [.apple])
    }

    @Test func appleNeverAbsentWhenGooglePresent() {
        // Misconfiguration: tenant/coordinators say Google yes, Apple no.
        // The model must hide Google too rather than exposing it alone.
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: false, supportsGoogle: true
            ),
            coordinators: [.google: MockCoordinator(provider: .google, outcome: .cancelled)],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        #expect(model.availableProviders.isEmpty)
        #expect(!model.availableProviders.contains(.google))
    }

    @Test func availableProvidersEmptyWhenSocialSignInNeverConfigured() {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)
        #expect(model.availableProviders.isEmpty)
    }

    // MARK: - Token exchange + first-sign-in name/email handling

    @Test func successfulCredentialExchangesTokenAndStoresSession() async {
        let recorder = Recorder<MockSocialAuth.Call>()
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true
            ),
            coordinators: [.apple: MockCoordinator(
                provider: .apple,
                outcome: .credential(SocialCredential(idToken: "apple-id-token", name: "First Timer"))
            )],
            socialAuth: MockSocialAuth(result: .success(Self.session(name: "First Timer")), recordedCall: recorder)
        )

        await model.signIn(with: .apple)

        #expect(model.phase == .idle)
        #expect(model.sessions.isSignedIn)
        guard let call = recorder.all.first else {
            Issue.record("expected socialSignIn to be called")
            return
        }
        #expect(call.provider == .apple)
        #expect(call.idToken == "apple-id-token")
        #expect(call.tenantId == Self.tenantId)
        #expect(call.name == "First Timer") // forwarded on first sign-in
    }

    /// Repeat sign-in: Apple sends no `fullName` after the first
    /// authorization — the coordinator reports `name: nil`, and that nil
    /// must reach the server call as-is (not synthesized client-side), so
    /// the server's own fallback (token claim, then email local part)
    /// applies.
    @Test func repeatSignInForwardsNilNameUnchanged() async {
        let recorder = Recorder<MockSocialAuth.Call>()
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true
            ),
            coordinators: [.apple: MockCoordinator(
                provider: .apple,
                outcome: .credential(SocialCredential(idToken: "apple-id-token-2", name: nil))
            )],
            socialAuth: MockSocialAuth(result: .success(Self.session(name: "Returning User")), recordedCall: recorder)
        )

        await model.signIn(with: .apple)

        #expect(model.phase == .idle)
        guard let call = recorder.all.first else {
            Issue.record("expected socialSignIn to be called")
            return
        }
        #expect(call.name == nil)
    }

    @Test func serverErrorSurfacesFriendlyMessageAndKeepsSignedOut() async {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsGoogle: true
            ),
            coordinators: [.google: MockCoordinator(
                provider: .google, outcome: .credential(SocialCredential(idToken: "tok", name: nil))
            )],
            socialAuth: MockSocialAuth(result: .failure(SocialAuthError.unverifiedEmail), recordedCall: nil)
        )

        await model.signIn(with: .google)

        #expect(!model.sessions.isSignedIn)
        #expect(model.phase == .failed(message: "That account's email isn't verified with the provider yet."))
    }

    // MARK: - socialStep (bamware-ios#12) — the two waits are distinguishable

    @Test func socialStepGoesThroughWaitingForProviderThenExchangingTokenThenClears() async {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)
        let modelBox = TestBox(value: model)
        let stepRecorder = Recorder<AccountModel.SocialStep?>()

        model.socialSignIn = SocialSignInSupport(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true
            ),
            coordinators: [.apple: StepCapturingCoordinator(
                provider: .apple,
                outcome: .credential(SocialCredential(idToken: "apple-id-token", name: "Tester")),
                modelBox: modelBox,
                recorder: stepRecorder
            )],
            socialAuth: StepCapturingSocialAuth(
                modelBox: modelBox, recorder: stepRecorder,
                result: .success(Self.session(name: "Tester"))
            )
        )

        #expect(model.socialStep == nil)
        await model.signIn(with: .apple)

        // Captured in call order: the coordinator sees `.waitingForProvider`
        // (the native sheet leg), the server exchange sees
        // `.exchangingToken` — proving the model tells the two waits apart
        // and sets each one before the corresponding await, not after.
        #expect(stepRecorder.all == [.waitingForProvider, .exchangingToken])
        #expect(model.socialStep == nil) // cleared once the flow settles
        #expect(model.phase == .idle)
    }

    @Test func cancelledSignInClearsSocialStep() async {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)
        model.socialSignIn = SocialSignInSupport(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsApple: true
            ),
            coordinators: [.apple: MockCoordinator(provider: .apple, outcome: .cancelled)],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        await model.signIn(with: .apple)

        #expect(model.socialStep == nil)
    }

    @Test func serverErrorClearsSocialStep() async {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsGoogle: true
            ),
            coordinators: [.google: MockCoordinator(
                provider: .google, outcome: .credential(SocialCredential(idToken: "tok", name: nil))
            )],
            socialAuth: MockSocialAuth(result: .failure(SocialAuthError.unverifiedEmail), recordedCall: nil)
        )

        await model.signIn(with: .google)

        #expect(model.socialStep == nil)
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }

    @Test func unavailableCoordinatorClearsSocialStep() async {
        let model = makeModel(
            config: AccountTenantConfig(
                tenantId: Self.tenantId, authBaseURL: URL(string: "https://auth.test")!,
                keychainService: "svc", supportsGoogle: true
            ),
            coordinators: [.google: MockCoordinator(
                provider: .google, outcome: .unavailable(message: "Google sign-in isn't available yet.")
            )],
            socialAuth: MockSocialAuth(recordedCall: nil)
        )

        await model.signIn(with: .google)

        #expect(model.socialStep == nil)
    }
}
