# ADR-0001: Core Architecture -- Offline-First with Local Persistence

## Status

Accepted

## Context

Neb currently operates online-only. The SDK streams events, view models consume them, views render. If the SDK doesn't sync, the app shows nothing. There is no local search, no offline access, no message cache the app controls.

The SDK (matrix-rust-sdk) handles protocol, crypto, and sync. It has an internal SQLite store, but it's opaque -- the app can't query it. Features like local search, instant launch with cached data, and offline composition require a persistence layer the app owns.

Additionally, credentials are stored as plain JSON on disk (`session.json`), and the SDK's crypto store has no passphrase -- it's unencrypted at rest.

## Decisions

### 1. Local Database with GRDB and SQLCipher

Add a local SQLite database managed by GRDB. Encrypt it with SQLCipher. GRDB is a Swift package that works on both macOS and iOS, supporting the cross-platform goal.

The database stores:
- Room metadata (name, avatar, last message, unread count, DM assignment)
- Timeline events (messages, state events, media references)
- User profiles (display name, avatar URL)
- DM assignments (which room is the designated DM per user)
- Search index (full-text search over message content)

The database is a cache -- the Matrix server (via the SDK) is the source of truth. If the database is lost, it rebuilds from sync.

### 2. Credentials in the Keychain

Move session credentials (access token, user ID, device ID, homeserver URL) from `session.json` to the platform Keychain. Following Element X's pattern: store a `RestorationToken` struct (JSON-encoded) in the Keychain, keyed by user ID.

Generate a random passphrase on first login for:
- The SDK's crypto store encryption (passed to `ClientBuilder`)
- The GRDB/SQLCipher database encryption key

Both passphrases stored in the Keychain alongside the session.

### 3. One DM Per User

The SDK can report multiple rooms with `isDirect=true` for the same user (created by other clients). Neb enforces a single DM per user:

- On first encounter, the room with the most recent `lastMessageTimestamp` is automatically designated as the DM.
- The assignment is persisted in the local database.
- Once assigned, it sticks -- no re-evaluation.
- Non-designated rooms with the same user appear under Groups.

### 4. NebCore Stays Platform-Agnostic

NebCore (the Swift Package) must not import AppKit or UIKit. Platform-specific utilities (HTMLRenderer, MarkdownConverter, AttributedStringFormatter) live in the app target.

Cross-platform guards (`#if canImport(AppKit)`) are acceptable for shared types like image caching (`NSImage`/`UIImage` aliased as `PlatformImage`).

### 5. Linter for SDK Import Boundary

Add a build phase or linter rule that prevents `import MatrixRustSDK` outside of `NebCore/Sources/NebCore/Adapters/`. This enforces the adapter seam with multiple developers.

## Consequences

- Launch is faster -- the app renders from local data while sync fills in updates.
- Search works locally and instantly.
- DM deduplication is handled at the data layer, not the view layer.
- Credentials are protected by the OS Keychain instead of plain files.
- The database adds complexity -- schema migrations, sync-to-database merging, cache invalidation.
- GRDB becomes a dependency of NebCore (but it's lightweight and cross-platform).
- Existing `session.json` persistence in `MatrixAuthAdapter` needs to be replaced with Keychain operations.
