#if DEBUG
import BamwareCore
import SwiftUI

/// Bamware debug environment switching — the UI half. Debug-only; see
/// `DebugBackendEnvironment` in BamwareCore for the adoption story.

/// Environment picker sheet: one row per case, checkmark on the current one.
public struct DebugEnvironmentPicker<Env: DebugBackendEnvironment>: View {
    @Bindable private var store: DebugEnvironmentStore<Env>

    public init(store: DebugEnvironmentStore<Env>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List(Array(Env.allCases)) { env in
                Button {
                    store.current = env
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(env.label)
                            Text(env.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.current == env {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(Text(verbatim: "Environment"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
    }
}

/// Warning badge shown whenever the app is pointed off production.
public struct DebugEnvironmentBadge<Env: DebugBackendEnvironment>: View {
    private let store: DebugEnvironmentStore<Env>

    public init(store: DebugEnvironmentStore<Env>) {
        self.store = store
    }

    public var body: some View {
        if store.current != Env.production {
            Text(verbatim: "ENV: \(store.current.label)")
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.orange, in: Capsule())
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// The easter-egg gate: fires `action` after `count` cumulative taps
    /// (classic "tap the version number" pattern).
    public func debugTapGate(count: Int = 5, action: @escaping () -> Void) -> some View {
        modifier(DebugTapGate(threshold: count, action: action))
    }
}

private struct DebugTapGate: ViewModifier {
    let threshold: Int
    let action: () -> Void
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                taps += 1
                if taps >= threshold {
                    taps = 0
                    action()
                }
            }
    }
}
#endif
