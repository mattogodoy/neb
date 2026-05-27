# ADR-0002: Keep Protocol Pattern, Add Database Internally

## Status

Accepted (revised -- originally proposed NebClient, decided to keep protocols)

## Context

The current architecture exposes multiple protocols to the app layer: `RoomServiceProtocol`, `SyncServiceProtocol`, `TypingServiceProtocol`, `CryptoServiceProtocol`, `AuthServiceProtocol`, `NotificationServiceProtocol`. Each has a corresponding adapter that wraps SDK calls. View models receive these protocols through dependency injection.

With the introduction of a local database (ADR-0001), the question was whether to replace this with a single unified API (`NebClient`) or evolve the existing pattern.

A single `NebClient` was considered (Telegram's `TelegramEngine` pattern). Element X uses the protocol-per-domain pattern, similar to what Neb has now. Both work.

## Decision

Keep the existing protocol pattern. The database is an internal detail of the adapter layer.

The protocols stay as the seam between NebCore and the app. View models continue to receive protocols through init. Test mocks continue to implement protocols. AppState continues to wire dependencies.

What changes internally:

- Adapters gain a shared database dependency (GRDB `DatabaseQueue`).
- Adapters write SDK events to the database and serve view models from the database.
- An internal SDK observer layer listens to the SDK sync streams and populates the database.
- The protocols may evolve to better reflect the app's needs (not the SDK's shape), but they remain the public interface.

```
ViewModel → Protocol → Adapter → Database ← SDK Observer ← MatrixRustSDK
```

The database and SDK observer are implementation details behind the adapter. The app never sees them.

## Why Not NebClient

- The current protocol pattern is working and well-tested.
- Mocks are scoped per domain -- a timeline test only mocks timeline.
- Protocols match Element X's approach, which uses the same SDK.
- A single NebClient risks becoming a god object.
- The migration cost is high for marginal benefit.

## Consequences

- Smaller change from the current architecture -- protocols and view models stay the same.
- Adapters get more complex internally (SDK + database), but their interface stays simple.
- Testing is unchanged -- mock services, no database needed in tests.
- New features can still be added as new protocols when needed.
- AppState still wires adapters, but passes a shared database instance to each.
