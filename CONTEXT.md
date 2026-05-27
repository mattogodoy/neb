# Neb Domain Model

## What Neb Is

Neb is a native macOS Matrix client. Named after the Nebuchadnezzar from The Matrix. Aims to feel native and fast, unlike Element X which feels like a mobile app on desktop. Future iOS target planned.

## Core Concepts

- **Room** -- a Matrix room. Contains a timeline, members, and state. Can be a direct message or a group.
- **Direct Message (DM)** -- a room with exactly one other user, designated as "the" conversation with that user. Neb enforces one DM per user. If the SDK reports multiple DM rooms with the same user, the one with the most recent activity is automatically chosen as the DM on first encounter, and that choice persists. Other rooms with the same user appear as groups.
- **Group** -- any room that is not the designated DM for a user. Includes rooms the SDK marks as `isDirect` if they are not the chosen DM.
- **Timeline** -- the ordered stream of events in a room. The SDK caches events in its internal database; Neb reads from the SDK's timeline API.
- **Message** -- a timeline event with displayable content (text, media, replies, reactions). The core understands all Matrix message types, not just text.
- **Search Index** -- a lightweight FTS5 index (GRDB/SQLCipher) that indexes message text as it flows through the timeline stream. Not a copy of the SDK's data -- just a search-optimized index of message bodies.
- **Session** -- the authenticated connection to a homeserver. Credentials (access token, user ID, device ID) and the crypto store passphrase are stored in the platform Keychain, not in plain files.

## Architecture Layers

```
Platform App (Neb/ or future iOS/)
  Views -- SwiftUI + platform-specific code (AppKit / UIKit)
  ViewModels -- @Observable @MainActor, drive UI
  Utilities -- platform-specific text rendering (HTMLRenderer, MarkdownConverter)

NebCore (Swift Package, platform-agnostic)
  Services -- protocol definitions (seam between app and core)
  Adapters -- implement protocols using MatrixRustSDK
  Models -- NebRoom, NebMessage, NebUser, etc.
  Search Index -- GRDB/SQLCipher FTS5 index, populated from timeline stream
```

- **Services (Protocols)** -- the public API. View models receive protocols through dependency injection. Each protocol covers a domain: rooms, timeline, auth, crypto, typing, notifications.
- **Adapters** -- implement the protocols. Read from the SDK's API (which is backed by the SDK's internal cache). Delegate actions (send, edit, react) to the SDK.
- **Search Index** -- GRDB/SQLCipher, indexes message bodies for local full-text search. Populated as a side effect of the timeline stream. Not a duplicate of the SDK's data.

The SDK is the source of truth for all Matrix data. The search index is the only separate persistence Neb maintains (alongside DM assignments in UserDefaults and credentials in the Keychain).

## Rules

- Views and ViewModels never import MatrixRustSDK. They consume protocols from NebCore. Enforced by a linter.
- NebCore does not import AppKit or UIKit. Platform-specific code lives in the app target. Cross-platform guards (`#if canImport`) are acceptable for types like `NSImage`/`UIImage` in shared utilities like avatar caching.
- One DM per user. Automatic assignment on first encounter, persists in UserDefaults.
- Credentials in the Keychain, never in plain files.
- The search index is encrypted with SQLCipher. The encryption key is a random passphrase stored in the Keychain.
- The Rust SDK is the source of truth for protocol, crypto, and sync. The search index can be rebuilt by paginating through room timelines.
