# Neb — Native macOS Matrix Client

Neb (named after the Nebuchadnezzar ship from The Matrix) is a native macOS Matrix client built with SwiftUI and matrix-rust-sdk. It aims to be fast and native-feeling, unlike Element X which feels like a mobile app on desktop.

## Quick Start

```bash
# Generate Xcode project (required after adding/removing files)
xcodegen generate

# Build NebCore library (fast, no Xcode needed)
cd NebCore && swift build

# Run tests
cd NebCore && swift test

# Open in Xcode and run
open Neb.xcodeproj
```

## Architecture

```
Neb App (SwiftUI views, AppState)
  └─ NebCore (Swift Package)
       ├─ ViewModels   — @Observable @MainActor, drive UI
       ├─ Services     — Protocol definitions (abstraction boundary)
       ├─ Adapters     — Implement protocols using MatrixRustSDK
       └─ Models       — NebRoom, NebMessage, NebUser, etc.
```

**Key rule:** Views and ViewModels never import MatrixRustSDK. They depend on service protocols only. The adapters are the only code that touches SDK types.

**Dependency flow:** View → ViewModel → ServiceProtocol ← Adapter → MatrixRustSDK

**AppState** (`Neb/AppState.swift`) is the root coordinator — creates all adapters, wires dependencies via closures, manages login/sync lifecycle.

## Project Structure

```
Neb/                              # macOS app target
├── NebApp.swift                  # @main entry point
├── AppState.swift                # Root dependency container
└── Views/
    ├── Common/AvatarView.swift   # Reusable avatar with async image loading
    ├── LoginView.swift
    ├── MainView.swift            # NavigationSplitView shell
    ├── NewDMSheet.swift
    ├── Sidebar/                  # Room list sidebar
    ├── Timeline/                 # Messages, composer, day separators, read receipts
    └── Verification/             # Device and contact verification flows

NebCore/                          # Swift Package (shared library)
├── Package.swift                 # swift-tools-version: 6.0
├── Sources/NebCore/
│   ├── Models/                   # NebRoom, NebMessage, NebUser, VerificationState, UserColorGenerator
│   ├── Services/                 # Protocol definitions + AvatarImageCache
│   ├── Adapters/                 # MatrixAuth/Sync/Room/Crypto/Notification adapters
│   └── ViewModels/               # Login, RoomList, Timeline, Verification, NewDM
└── Tests/NebCoreTests/
    ├── Mocks/                    # Mock service implementations
    └── *Tests.swift              # ViewModel tests using Swift Testing framework

project.yml                       # XcodeGen spec → generates Neb.xcodeproj
```

## Build System

- **XcodeGen** generates `Neb.xcodeproj` from `project.yml`. Run `xcodegen generate` after adding/removing files.
- **NebCore** is a local Swift Package imported by the Xcode project.
- **Deployment target:** macOS 14.0 (Sonoma)
- **Swift tools version:** 6.0 (strict concurrency)
- **SDK dependency:** `matrix-rust-components-swift` v26.5.13+ (provides `MatrixRustSDK`)

## SDK Adapter Pattern

Each Matrix operation is wrapped in an adapter implementing a protocol:

```swift
// Protocol (in Services/)
public protocol RoomServiceProtocol: Sendable {
    func timelineStream(roomID: String) -> AsyncStream<[NebMessage]>
    func sendMessage(roomID: String, body: String) async throws
}

// Adapter (in Adapters/)
public final class MatrixRoomAdapter: RoomServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    // ... wraps MatrixRustSDK calls
}
```

Adapters receive a `() -> Client?` closure to access the logged-in SDK client. This avoids retain cycles and lets adapters work without knowing about AppState.

## SDK Listener Retention

SDK listener objects (room list, timeline, verification delegates) MUST be retained as properties on the adapter. If they're local variables, the Rust SDK will deallocate them and crash. This was a major debugging issue — always store listeners as instance properties.

## Concurrency Patterns

- ViewModels use `@Observable @MainActor` (no @Published)
- Adapters use `@unchecked Sendable` (SDK objects aren't natively Sendable)
- Mutable state in listeners uses `nonisolated(unsafe)` for Swift 6 compatibility
- Background tasks stored as `@ObservationIgnored nonisolated(unsafe) var task: Task<Void, Never>?`
- `deinit` cancels tasks to prevent leaks

## Testing

Tests use Swift Testing framework (`@Test`, `#expect`). Run from NebCore directory:

```bash
cd NebCore && swift test
```

The test target has `unsafeFlags` in Package.swift for CLT-only environments (Testing.framework discovery). With full Xcode installed, these flags may need to be removed.

All ViewModels are tested against mock service implementations in `Tests/NebCoreTests/Mocks/`.

## Logging

Uses `os.Logger` with subsystem `"com.neb.app"` and per-module categories:
- `Auth` — login, session restore, logout
- `Sync` — room list updates, sync service state
- `Room` — timeline events, message counts
- `Crypto` — verification flow, key recovery

## Known Quirks

- **Homeserver URL hardcoded** in `AppState.homeserverURL` as `"https://matrix.matto.io"`. Used for avatar image loading via the SDK's media API. Should be extracted from the stored session.
- **Cross-signing on login** — `autoEnableCrossSigning` and `autoEnableBackups` are enabled on the ClientBuilder. First login with a fresh crypto store can take 1-2 minutes. Subsequent logins reuse the crypto store and are fast. Do NOT clear the `data/` directory on login — only clear `session.json`.
- **Sliding sync** — uses `.discoverNative`. The homeserver must support native sliding sync. Room list entries require `setFilter(kind: .all(filters: []))` to start flowing.
- **Linker warnings** — suppressed with `-Wl,-w` in project.yml. The SDK binary targets macOS 26.4 while we target 14.0.
- **Room subscription** — rooms must be explicitly subscribed via `roomListService.subscribeToRooms()` before their timeline delivers events.
- **Debounced room list** — room list updates are debounced (100ms) to avoid redundant async room info fetches from rapid SDK diff callbacks.
- **Avatar loading** — uses SDK's `client.getMediaThumbnail()` for authenticated media access, not raw HTTP. Images cached in `AvatarImageCache` (NSCache, in-memory only).
- **Contact verification** — cannot re-verify an already-verified user (SDK throws "User is already verified"). Device verification can be re-done.

## Session Persistence

Session data stored in the app sandbox at `~/Library/Containers/com.neb.app/Data/Library/Application Support/Neb/`:
- `session.json` — access token, user ID, device ID, homeserver URL
- `data/` — SDK state + crypto SQLite stores (device keys, cross-signing)
- `cache/` — SDK media + event cache

On login: only `session.json` is cleared. `data/` and `cache/` are preserved to reuse crypto keys (avoiding slow key re-upload). On logout: everything is cleared.

## Entitlements

The app is sandboxed (`com.apple.security.app-sandbox`) with network client access (`com.apple.security.network.client`). These are in `Neb/Neb.entitlements` and referenced in `project.yml`.
