import Foundation
import Testing
@testable import BamwarePush

/// `PushRegistrar`: permission → register → upload → re-upload on token
/// change → delete on sign-out (bamware-ios#6). Every dependency is a fake;
/// nothing here touches `UNUserNotificationCenter`, `UIApplication`, the
/// network, or `UserDefaults`-backed keychain state.
@Suite struct PushRegistrarTests {
    private static func makeRegistrar(
        deviceId: String = "device-1",
        permissions: FakePushPermissionRequester = FakePushPermissionRequester(),
        remoteRegistrar: FakeRemoteNotificationRegistrar = FakeRemoteNotificationRegistrar(),
        deviceClient: FakePushDeviceClient = FakePushDeviceClient(),
        bearer: FakePushBearerProvider = FakePushBearerProvider(token: "bearer-token"),
        knownTypes: [String] = ["matches", "messages"]
    ) -> PushRegistrar {
        let settings = PushSettings(
            knownTypes: knownTypes,
            defaults: UserDefaults(suiteName: "PushRegistrarTests-\(UUID().uuidString)")!,
            storageKey: "prefs"
        )
        return PushRegistrar(
            configuration: .init(deviceId: deviceId, platform: "ios"),
            permissions: permissions,
            remoteRegistrar: remoteRegistrar,
            deviceClient: deviceClient,
            bearer: bearer,
            settings: settings
        )
    }

    // MARK: - Token upload

    @Test func uploadsTokenWithBearerDeviceIdPlatformAndPreferences() async {
        let deviceClient = FakePushDeviceClient()
        let bearer = FakePushBearerProvider(token: "bearer-token")
        let registrar = Self.makeRegistrar(deviceId: "device-42", deviceClient: deviceClient, bearer: bearer)

        await registrar.didReceiveDeviceToken(hex: "abc123")

        let calls = await deviceClient.registerCalls
        #expect(calls.count == 1)
        #expect(calls[0].deviceId == "device-42")
        #expect(calls[0].token == "abc123")
        #expect(calls[0].platform == "ios")
        #expect(calls[0].bearerToken == "bearer-token")
        #expect(calls[0].preferences == ["matches": true, "messages": true])
    }

    @Test func convertsRawTokenDataToHex() async {
        let deviceClient = FakePushDeviceClient()
        let registrar = Self.makeRegistrar(deviceClient: deviceClient)

        await registrar.didReceiveDeviceToken(Data([0x00, 0xFF, 0x1A]))

        let calls = await deviceClient.registerCalls
        #expect(calls.count == 1)
        #expect(calls[0].token == "00ff1a")
    }

    @Test func sendsCustomizedPreferences() async {
        let deviceClient = FakePushDeviceClient()
        let defaults = UserDefaults(suiteName: "PushRegistrarTests-custom-\(UUID().uuidString)")!
        let settings = PushSettings(knownTypes: ["matches", "messages"], defaults: defaults, storageKey: "prefs")
        settings.setEnabled(false, for: "messages")

        let registrar = PushRegistrar(
            configuration: .init(deviceId: "device-1"),
            permissions: FakePushPermissionRequester(),
            remoteRegistrar: FakeRemoteNotificationRegistrar(),
            deviceClient: deviceClient,
            bearer: FakePushBearerProvider(token: "bearer-token"),
            settings: settings
        )

        await registrar.didReceiveDeviceToken(hex: "abc123")

        let calls = await deviceClient.registerCalls
        #expect(calls[0].preferences == ["matches": true, "messages": false])
    }

    // MARK: - Re-upload on token change

    @Test func reuploadsWhenTokenChanges() async {
        let deviceClient = FakePushDeviceClient()
        let registrar = Self.makeRegistrar(deviceClient: deviceClient)

        await registrar.didReceiveDeviceToken(hex: "token-a")
        await registrar.didReceiveDeviceToken(hex: "token-b")

        let calls = await deviceClient.registerCalls
        #expect(calls.count == 2)
        #expect(calls[0].token == "token-a")
        #expect(calls[1].token == "token-b")
    }

    // MARK: - Delete on sign-out

    @Test func deletesDeviceOnSignOutWithBearer() async {
        let deviceClient = FakePushDeviceClient()
        let bearer = FakePushBearerProvider(token: "bearer-token")
        let registrar = Self.makeRegistrar(deviceId: "device-7", deviceClient: deviceClient, bearer: bearer)

        await registrar.deleteOnSignOut()

        let calls = await deviceClient.deleteCalls
        #expect(calls.count == 1)
        #expect(calls[0].deviceId == "device-7")
        #expect(calls[0].bearerToken == "bearer-token")
    }

    @Test func deleteOnSignOutNoOpsWithoutBearer() async {
        let deviceClient = FakePushDeviceClient()
        let bearer = FakePushBearerProvider(token: nil)
        let registrar = Self.makeRegistrar(deviceClient: deviceClient, bearer: bearer)

        await registrar.deleteOnSignOut()

        let calls = await deviceClient.deleteCalls
        #expect(calls.isEmpty)
    }

    // MARK: - Permission denied path

    @Test func permissionDeniedNeverRegistersForRemoteNotifications() async {
        let permissions = FakePushPermissionRequester(authorizationGrantResult: false)
        let remoteRegistrar = FakeRemoteNotificationRegistrar()
        let registrar = Self.makeRegistrar(permissions: permissions, remoteRegistrar: remoteRegistrar)

        let granted = await registrar.requestPermissionAndRegister()

        #expect(granted == false)
        let requestCount = await permissions.requestCount
        #expect(requestCount == 1)
        let registerCallCount = await remoteRegistrar.callCount
        #expect(registerCallCount == 0)
    }

    @Test func alreadyDeniedStatusDoesNotRePrompt() async {
        let permissions = FakePushPermissionRequester()
        await permissions.setAuthorizationStatus(.denied)
        let remoteRegistrar = FakeRemoteNotificationRegistrar()
        let registrar = Self.makeRegistrar(permissions: permissions, remoteRegistrar: remoteRegistrar)

        let granted = await registrar.requestPermissionAndRegister()

        #expect(granted == false)
        // No re-prompt: requestAuthorization() was never called because the
        // status was already determined (.denied) — BrewDesk's reused
        // policy.
        let requestCount = await permissions.requestCount
        #expect(requestCount == 0)
        let registerCallCount = await remoteRegistrar.callCount
        #expect(registerCallCount == 0)
    }

    @Test func permissionGrantedRegistersForRemoteNotifications() async {
        let permissions = FakePushPermissionRequester(authorizationGrantResult: true)
        let remoteRegistrar = FakeRemoteNotificationRegistrar()
        let registrar = Self.makeRegistrar(permissions: permissions, remoteRegistrar: remoteRegistrar)

        let granted = await registrar.requestPermissionAndRegister()

        #expect(granted)
        let registerCallCount = await remoteRegistrar.callCount
        #expect(registerCallCount == 1)
    }

    // MARK: - No bearer -> no upload

    @Test func noBearerMeansNoUpload() async {
        let deviceClient = FakePushDeviceClient()
        let bearer = FakePushBearerProvider(token: nil)
        let registrar = Self.makeRegistrar(deviceClient: deviceClient, bearer: bearer)

        await registrar.didReceiveDeviceToken(hex: "abc123")

        let calls = await deviceClient.registerCalls
        #expect(calls.isEmpty)
    }
}
