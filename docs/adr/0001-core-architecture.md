# ADR-0001: Core Architecture -- Local Message Database with SDK as Sync Layer

## Status

Accepted (revised twice -- originally proposed full local database, reduced to search index only, then expanded to full message database)

## Context

Neb uses the matrix-rust-sdk for protocol, crypto, and sync. The SDK has its own internal SQLite stores (state, crypto, event cache, media) that persist data between launches. The SDK's data is encrypted at the application level (per-value encryption) and is not directly queryable.

The question was whether to build a full local persistence layer on top of the SDK, or lean on the SDK's existing storage.

After investigating:
- The SDK already stores room metadata, events, members, profiles, read receipts, and a send queue.
- The SDK loads from cache on startup -- session restore is already fast.
- Element X (same SDK) does not maintain a separate database.
- The SDK's database is tightly coupled to its internals -- duplicating it would mean maintaining two storage systems.

## Decisions

### 1. Local Database is the Message Store

The UI reads messages from Neb's local GRDB/SQLCipher database, not the SDK's timeline API. The SDK is the sync and network layer -- it fetches events from the server and decrypts them. The adapters write to the database. View models observe the database reactively via GRDB `ValueObservation`.

The SDK's event cache is a thin sliding window (~10 items per room via sliding sync). It does not store full conversation history. A background backfill worker paginates backwards from the server to fill in historical messages.

See `docs/superpowers/specs/2026-05-28-local-message-database-design.md` for the full spec.

### 2. Full Message Database with GRDB and SQLCipher

The database stores everything needed to render messages: event ID, room ID, sender ID, body, formatted body, timestamp, edit state, send status. Reactions and read receipts are in separate normalized tables. Profiles (display name, avatar) are cached. FTS5 provides full-text search on message bodies.

Encrypted with SQLCipher using the passphrase from Keychain.

### 3. DM Assignments in the Local Database

DM assignment (which room is "the" DM per user) is stored in the same GRDB/SQLCipher database. A simple table mapping `directUserID → roomID`. Shares the same encryption and lifecycle.

### 4. Credentials in the Keychain (implemented)

Session credentials moved from `session.json` to the macOS/iOS Keychain. A random passphrase for the SDK's crypto store is generated on login and stored in the Keychain. See the Auth rewrite for implementation details.

### 5. NebCore Stays Platform-Agnostic (implemented)

AppKit-dependent utilities moved to the app target. NebCore imports only Foundation, Security, and MatrixRustSDK.

### 6. Linter for SDK Import Boundary

Add a build phase or linter rule that prevents `import MatrixRustSDK` outside of adapter code.

## What We Don't Build (Yet)

- **Room metadata database** -- room name, avatar, member count still come from the SDK's sync stream. Future work may move this to the database.
- **Media cache** -- the SDK has `matrix-sdk-media.sqlite3`. Future work may add local media storage.

## Consequences

- Instant room loads -- messages are in the local database, no server round-trip.
- Full offline access -- conversations are readable without network.
- Complete local search -- FTS5 covers all indexed messages.
- Background backfill fills in history progressively.
- Local echo for sends -- pending messages appear immediately, reconciled on confirmation.
- More complex than the previous search-index-only approach -- schema migrations, write coordination, deduplication.
- The SDK is still the authority for protocol, crypto, and sync. The database can be rebuilt by re-running the backfill worker.
- DM assignments and credentials are unchanged from the previous revision.
