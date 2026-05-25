# Neb

A native macOS Matrix client built with SwiftUI. Fast, snappy, and feels like a Mac app — not a mobile app running on your computer.

Named after the [Nebuchadnezzar](https://matrix.fandom.com/wiki/Nebuchadnezzar), the hovercraft from The Matrix.

## Why

[Element X](https://element.io/download) is the best Matrix client available, but on macOS it feels sluggish and non-native. Neb aims to fix that by being a truly native SwiftUI app that talks to Matrix via the same [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk) that Element X uses — but with a UI built specifically for Mac.

## Features

- Native macOS UI with `NavigationSplitView`, keyboard shortcuts, and system appearance
- End-to-end encryption (E2EE) with full key management
- Device verification (SAS emoji flow) and contact verification
- Recovery key support for restoring encrypted message history
- Room list with collapsible DM/Group sections, search, and unread badges
- Message timeline with grouping, day separators, and inline timestamps
- User avatars with async loading and initial-letter fallbacks
- Read receipts shown as tiny avatar indicators
- Send status indicators (sending, sent, failed)
- Session persistence with fast restore on relaunch
- Native macOS notifications with dock badge count
- Create new direct messages
- Cross-signing and key backup (automatic on login)

## Screenshots

*Coming soon*

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Xcode 16+**
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — generates the Xcode project from `project.yml`

## Setup

```bash
# Clone the repo
git clone https://github.com/mattogodoy/neb.git
cd neb

# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Neb.xcodeproj
```

Select the **Neb** scheme, press **Cmd+R** to build and run.

### First launch

1. Enter your homeserver URL, username, and password
2. First login may take 1-2 minutes (cross-signing key setup)
3. Subsequent launches restore the session instantly
4. Verify the device from another client (e.g. Element X) to decrypt E2EE messages

## Architecture

Neb uses a layered architecture with a clean separation between UI and the Matrix SDK:

```
Neb App (SwiftUI)
  └─ NebCore (Swift Package)
       ├─ ViewModels     @Observable, drive UI state
       ├─ Services        Protocol definitions (abstraction boundary)
       ├─ Adapters        Implement protocols using MatrixRustSDK
       └─ Models          NebRoom, NebMessage, NebUser, etc.
```

Views and ViewModels never import `MatrixRustSDK`. They depend on service protocols only. The adapters are the only code that touches SDK types. This means:

- ViewModels are fully testable with mock services
- The SDK can be updated or replaced without touching the UI
- The same `NebCore` package can be shared with an iOS target in the future

### Key dependencies

| Dependency | Purpose |
|---|---|
| [matrix-rust-components-swift](https://github.com/matrix-org/matrix-rust-components-swift) | Matrix protocol implementation (sync, E2EE, rooms, verification) |
| SwiftUI | Native macOS UI framework |
| XcodeGen | Xcode project generation from YAML |

## Building from source

### Build the library only (no Xcode required)

```bash
cd NebCore
swift build
```

### Run tests

```bash
cd NebCore
swift test
```

### Build the full app

```bash
xcodegen generate
xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build
```

Or open `Neb.xcodeproj` in Xcode and build from there.

## Project structure

```
Neb/                    macOS app target (SwiftUI views, AppState)
NebCore/                Swift Package (models, services, adapters, view models)
project.yml             XcodeGen configuration
docs/                   Design specs and implementation plans
```

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation, patterns, and known quirks.

## Homeserver requirements

Neb uses **Sliding Sync** (native) for efficient room list synchronization. Your homeserver must support it. Most modern Synapse installations (v1.94+) have native sliding sync support.

## Contributing

This project is in early development. Issues and PRs are welcome.

## License

MIT
