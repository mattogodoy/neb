# ADR-0001: Core Architecture -- SDK as Source of Truth with Search Index

## Status

Accepted (revised -- originally proposed full local database, reduced to search index only)

## Context

Neb uses the matrix-rust-sdk for protocol, crypto, and sync. The SDK has its own internal SQLite stores (state, crypto, event cache, media) that persist data between launches. The SDK's data is encrypted at the application level (per-value encryption) and is not directly queryable.

The question was whether to build a full local persistence layer on top of the SDK, or lean on the SDK's existing storage.

After investigating:
- The SDK already stores room metadata, events, members, profiles, read receipts, and a send queue.
- The SDK loads from cache on startup -- session restore is already fast.
- Element X (same SDK) does not maintain a separate database.
- The SDK's database is tightly coupled to its internals -- duplicating it would mean maintaining two storage systems.

## Decisions

### 1. SDK is the Source of Truth

The SDK's internal database is the canonical data store. Neb does not duplicate room metadata, events, members, or profiles in a separate database. The app reads from the SDK's API (`Room.roomInfo()`, `Room.latestEvent()`, `Room.timeline()`, etc.), which is backed by the SDK's cache.

### 2. Search Index with GRDB and SQLCipher

Add a lightweight FTS5 (full-text search) index in a separate SQLite database managed by GRDB. Encrypted with SQLCipher using the passphrase from Keychain.

The index stores only what's needed for search:
- `eventID`, `roomID`, `senderID`, `body`, `timestamp`
- FTS5 index on `body`

The index is populated as a side effect of the timeline stream -- as messages flow through the adapter, their text is indexed. The index is not a replacement for the SDK's storage. If lost, it rebuilds by paginating backwards through rooms.

Search results return event IDs, which the app uses to jump to context via the SDK's timeline API.

### 3. DM Assignments in UserDefaults

DM assignment (which room is "the" DM per user) is a small key-value mapping. Stored in UserDefaults as a `[String: String]` dictionary (`directUserID → roomID`). No database needed for this.

### 4. Credentials in the Keychain (implemented)

Session credentials moved from `session.json` to the macOS/iOS Keychain. A random passphrase for the SDK's crypto store is generated on login and stored in the Keychain. See the Auth rewrite for implementation details.

### 5. NebCore Stays Platform-Agnostic (implemented)

AppKit-dependent utilities moved to the app target. NebCore imports only Foundation, Security, and MatrixRustSDK.

### 6. Linter for SDK Import Boundary

Add a build phase or linter rule that prevents `import MatrixRustSDK` outside of `NebCore/Sources/NebCore/Adapters/`.

## What We Don't Build

- **Full message cache** -- the SDK already caches events in its encrypted SQLite store.
- **Room metadata database** -- the SDK provides `Room.roomInfo()` and `Room.latestEvent()` from cache.
- **Offline send queue** -- the SDK has `send_queue_events` built in.
- **Media cache** -- the SDK has `matrix-sdk-media.sqlite3`.

## Consequences

- Simpler architecture -- one source of truth (the SDK), one small index for search.
- No schema migration complexity for event/room/member storage.
- GRDB is only needed for the search index (lightweight dependency).
- Search is local and instant once indexed.
- If the SDK changes its internal storage format, Neb is unaffected (we don't read the SDK's database).
- DM assignments are simple and portable via UserDefaults.
- Credentials are protected by the OS Keychain.
