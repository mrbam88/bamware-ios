# bamware-ios
BAMware Swift Package


## Overview
Bamware iOS is a modular Swift Package designed as the core foundation for tenant-based applications, emphasizing Protocol-Oriented Programming (POP), Swift concurrency, and a clean architecture. It powers tenant-agnostic features like authentication, permissions, theming, and messaging, serving as the backbone for demo apps like `bamware-demo-app`.

### Repositories
- **Core**: `bamware-ios` - Private Swift Package containing `BamwareCore`, `BamwareUI`, and `BamwareMessaging`.
- **Demo**: `bamware-demo-app` - Public Xcode project showcasing `bamware-ios` features.

### Current State (March 25, 2025)
- **Core Features**:
  - `BamwareCore`: Authentication (`AuthService`, `DefaultAuthService`), Permissions (`UserPermissionsService`, `DefaultUserPermissionsService`), Tenants, Observability, Feature Flags—unit tests passing.
  - `BamwareUI`: Theming (`ThemeService`, `DefaultTheme`), `SmartText`—agnostic UI components.
  - `BamwareMessaging`: `Message`, `MessageRepository`, `MessageListView`—tenant-based messaging.
- **Demo App**: 
  - Runs—displays messages (“Hello, Bamware!”) after `validateToken("mock-token")`.
  - Uses Factory for Dependency Injection (DI)—`Container.demoTenant`.
- **Workspace**: `BamwareWorkspace.xcworkspace`—links `bamware-ios` and `bamware-demo-app` locally for fast development.

### Architecture
- **POP**: Protocols (`AuthService`)—implementations (`DefaultAuthService`)—tenant-shared.
- **DI**: Factory—`@Injected`—currently facing circular dependency issues (`AuthService` ↔ `UserPermissionsService`).
- **Combine**: `@Published`—reactive state—threading conflicts with SwiftUI (`DefaultAuthService`—`validateToken`).

### Recent Challenges
- **Combine**: `@Published currentUser`—background updates—SwiftUI main thread—fixed with `@MainActor` on `validateToken`.
- **Factory**: Circular dependencies—`DefaultAuthService` needs `UserPermissionsService`, which needs `AuthService`—mitigated with `setPermissionsService` post-init.
- **Workflow**: Slow—committing `bamware-ios` for every change—resolved with workspace linking local `bamware-ios`.

### Goals
- Stable DI—eliminate Factory cycles—consider `DIContainer` (like `CountriesSwiftUI`).
- Simplify Combine—reactive state without threading hassles—possible `@State` shift.
- Fast Workflow—workspace—local edits—live in `bamware-demo-app`.

### Next Steps
- Unit test `ContentView`—verify DI and permissions in `bamware-demo-app`.
- Polish `bamware-ios`—new core features (e.g., tenant switching).
- Review architecture—Combine vs. SwiftUI state, Factory vs. `DIContainer`.

