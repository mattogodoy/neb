# ADR-0002: NebClient as the Single Public API

## Status

Accepted

## Context

The current architecture exposes multiple protocols to the app layer: `RoomServiceProtocol`, `SyncServiceProtocol`, `TypingServiceProtocol`, `CryptoServiceProtocol`, `AuthServiceProtocol`, `NotificationServiceProtocol`. Each has a corresponding adapter that wraps SDK calls. View models receive these protocols through dependency injection.

This design has several problems:

- The app layer knows about the internal structure of the core (6 protocols, 6 adapters, wired through AppState).
- Adding a feature means adding a new protocol, adapter, mock, and wiring -- high ceremony for small changes.
- The protocols mirror the SDK's shape rather than the app's needs.
- With the introduction of a local database (ADR-0001), the adapters would need to both write to the database and serve view models -- two responsibilities that leak implementation details.

## Decision

Replace the multiple protocols with a single public API: `NebClient`.

`NebClient` is the only type the app imports from NebCore (besides models). It exposes methods and reactive streams organized by domain, not by SDK feature:

```
NebClient
  .auth        -- login, logout, restore session
  .rooms       -- room list stream, room metadata, DM assignment
  .timeline    -- message stream for a room, send, edit, react, delete
  .typing      -- send/receive typing indicators
  .search      -- full-text search across rooms
  .crypto      -- verification flows, key backup
  .media       -- upload, download, thumbnails
  .user        -- profile, presence
```

Internally, NebClient owns:
- The database (GRDB/SQLCipher) -- reads and writes
- The SDK observer -- subscribes to MatrixRustSDK sync streams, populates the database
- The SDK client -- delegates actions (send message, login, etc.)

The SDK observer and database are implementation details. The app never sees them. View models call `NebClient` methods and subscribe to its streams.

## Consequences

- The app has one dependency: `NebClient`. No protocol zoo, no adapter wiring.
- ViewModels are simpler -- they call one API instead of juggling multiple services.
- Testing: mock `NebClient` (or its sub-APIs) instead of 6 separate mock services.
- The current protocol/adapter pattern is retired. Migration is incremental -- new features go through `NebClient`, existing features migrate over time.
- `AppState` becomes much simpler -- creates `NebClient`, hands it to view models.
- The database and SDK observer can evolve independently without touching the public API.
