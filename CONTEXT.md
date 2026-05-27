# Neb Domain Model

## What Neb Is

Neb is a native macOS Matrix client. Named after the Nebuchadnezzar from The Matrix. Aims to feel native and fast, unlike Element X which feels like a mobile app on desktop. Future iOS target planned.

## Core Concepts

- **Room** -- a Matrix room. Contains a timeline, members, and state. Can be a direct message or a group.
- **Direct Message (DM)** -- a room with exactly one other user, designated as "the" conversation with that user. Neb enforces one DM per user. If the SDK reports multiple DM rooms with the same user, the one with the most recent activity is automatically chosen as the DM on first encounter, and that choice persists. Other rooms with the same user appear as groups.
- **Group** -- any room that is not the designated DM for a user. Includes rooms the SDK marks as `isDirect` if they are not the chosen DM.
- **Timeline** -- the ordered stream of events in a room. Neb persists timeline events locally for offline access and search.
- **Message** -- a timeline event with displayable content (text, media, replies, reactions). The core understands all Matrix message types, not just text.
- **Session** -- the authenticated connection to a homeserver. Credentials (access token, user ID, device ID) and the crypto store passphrase are stored in the platform Keychain, not in plain files.

## Architecture Layers

```
Platform App (Neb/ or future iOS/)
  Views -- SwiftUI + platform-specific code (AppKit / UIKit)
  Utilities -- platform-specific text rendering (HTMLRenderer, MarkdownConverter)

NebCore (Swift Package, platform-agnostic)
  ViewModels -- @Observable @MainActor, drive UI
  Database -- GRDB/SQLCipher, local persistence, search index
  Services -- protocol definitions (seam between core and SDK)
  Adapters -- implement protocols using MatrixRustSDK
  Models -- NebRoom, NebMessage, NebUser, etc.
```

## Rules

- Views and ViewModels never import MatrixRustSDK. Enforced by a linter.
- NebCore does not import AppKit or UIKit. Platform-specific code lives in the app target. Cross-platform guards (`#if canImport`) are acceptable for types like `NSImage`/`UIImage` in shared utilities like avatar caching.
- One DM per user. Automatic assignment on first encounter, persists in the local database.
- Credentials in the Keychain, never in plain files.
- The local database is encrypted with SQLCipher. The encryption key is a random passphrase stored in the Keychain.
- The Rust SDK is the source of truth for protocol, crypto, and sync. The local database is a cache that can be rebuilt from sync.
