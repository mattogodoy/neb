# Neb: Native macOS Matrix Client — Design Spec

## Overview

Neb is a native macOS Matrix client built with SwiftUI and matrix-rust-sdk-swift. It aims to replace Element X for users who want a fast, native Mac experience. The core differentiators are: truly native macOS UI, snappy performance, and reliable E2EE verification.

## Motivation

Element X — the current best Matrix client — has several problems on macOS:
- **Non-native UI**: looks and feels like a mobile app ported to desktop
- **Input lag**: emoji picker, opening chats, and general interactions feel slow
- **Unreliable notifications**: unread message counts drift out of sync
- **Slow startup**: a side effect of its non-native architecture

Neb addresses these by being a native SwiftUI app with no web views or cross-platform UI frameworks.

## Architecture

### Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Matrix SDK**: matrix-rust-sdk-swift (official Swift bindings for matrix-rust-sdk via UniFFI)
- **Package Manager**: Swift Package Manager
- **Minimum Deployment Target**: macOS 14 (Sonoma)
- **IDE**: Xcode

### Project Structure

Single Xcode project with three modules:

- **NebCore** (Swift package): all business logic — SDK abstraction layer, services, view models, data models. Shared between platforms.
- **Neb macOS** (app target): macOS-specific SwiftUI views, menu bar integration, keyboard shortcuts.
- **Neb iOS** (app target, future): iOS-specific SwiftUI views. Not built in the PoC but the structure supports it from day one.

### Layer Architecture

```
┌─────────────────────────────────────┐
│  Platform UI (macOS / iOS targets)  │  SwiftUI Views, platform-specific
├─────────────────────────────────────┤
│  View Models                        │  @Observable, in NebCore
├─────────────────────────────────────┤
│  Services (Swift protocols)         │  SyncService, RoomService,
│                                     │  CryptoService, NotificationService
├─────────────────────────────────────┤
│  SDK Adapter                        │  Concrete implementations wrapping
│                                     │  matrix-rust-sdk-swift
├─────────────────────────────────────┤
│  matrix-rust-sdk-swift              │  XCFramework, imported as dependency
└─────────────────────────────────────┘
```

### Key Architectural Boundary: The Services Layer

The Services layer consists of Swift protocols that define what the app needs from Matrix. View models and views never import or reference Rust SDK types directly.

Example protocols:
- `AuthService` — login, logout, session persistence
- `SyncService` — start/stop sync, expose room list and timeline updates as `AsyncStream`s
- `RoomService` — fetch room details, send messages, create DMs, manage read receipts
- `CryptoService` — cross-signing setup, device verification (SAS), contact verification, recovery key management
- `NotificationService` — register for notifications, compute badge counts

The SDK Adapter module provides concrete implementations of these protocols using matrix-rust-sdk-swift. This boundary provides:
- Testability: view models can be tested against mock service implementations
- Decoupling: if the Rust SDK changes its API, only the adapter changes
- Replaceability: the SDK can theoretically be swapped without touching the app layer

## Data Flow

### Sync Loop

1. After login, the SDK Adapter starts the matrix-rust-sdk sync loop
2. The adapter exposes updates as Swift `AsyncStream`s (room list changes, timeline events, verification requests)
3. Services consume these streams and transform Rust SDK types into Neb's own Swift model types (`NebRoom`, `NebMessage`, `NebUser`)
4. View models observe services via `@Observable` properties (macOS 14+ Observation framework)
5. SwiftUI views re-render automatically

### Local Persistence

matrix-rust-sdk maintains its own SQLite store for sync state, room data, and crypto keys. Neb does not maintain a separate database. App-level preferences (UI state, notification settings) use `UserDefaults`.

## macOS UI Design

### Layout: Two-Column with Collapsible Sections

Uses SwiftUI's `NavigationSplitView`:

- **Left sidebar (220pt)**: search field at top, then collapsible sections (Direct Messages, Groups). Each room row shows name, last message preview, timestamp, and unread badge.
- **Right content area**: conversation header (room name, verification status), message timeline, and message composer.

This layout mirrors Apple Messages in simplicity but adds organizational structure via collapsible sections. It scales naturally from a few DMs to many rooms.

### macOS-Native Behaviors

- Standard window management (resize, full screen, split view)
- Menu bar with keyboard shortcuts for common actions (new DM, search, mark all read)
- `Cmd+K` or `Cmd+T` quick switcher for jumping to a room by name
- Proper focus management and tab navigation
- System accent color support
- Dark/light mode following system appearance

## E2EE & Verification

### Key Management

Neb is a full standalone client — it generates and manages its own device keys:

1. On first login, device keys are generated and uploaded via the Rust SDK
2. Cross-signing keys are created and stored in Secret Storage (encrypted on server)
3. User is shown a recovery key once and prompted to save it
4. Recovery key can restore cross-signing on new devices

### Device Verification (SAS)

Flow when signing in on a new device:

1. New device signs in → existing device receives a verification request
2. User accepts on existing device → both devices display 7 emoji
3. User confirms emoji match on both sides → devices are cross-signed
4. Verification complete

UI requirements:
- Explicit state machine with clear visual states: waiting, comparing emoji, confirmed, failed, timed out
- Each state shows what the user should do next
- Failure states include actionable next steps and a retry button
- Timeout after 60 seconds of inactivity with clear messaging

### Contact Verification

DM conversations show the other user's verification status. Users can initiate SAS verification from within a chat — same emoji comparison flow, between two users rather than two devices.

### Addressing Element X's Verification Problems

Element X often gets stuck in ambiguous "verifying..." states. Neb addresses this by:
- Mapping the verification protocol to an explicit state machine with no ambiguous intermediate states
- Showing clear error messages when verification fails (not just "something went wrong")
- Implementing proper timeouts so the UI never hangs
- The Rust SDK handles the protocol correctly — the bugs in Element X are in its UI layer

## Notifications & Unread Counts

### macOS Notifications

- Built on `UserNotifications` framework (same as Messages, Mail)
- Notifications grouped by room
- Clicking a notification navigates directly to the room
- Dock icon badge count reflects total unread messages

### Unread Count Accuracy

Unread counts are derived directly from the SDK's sync state on every sync tick — not cached or computed separately:

- Read receipts are sent immediately when a room gains focus (no debouncing)
- Badge count is recomputed from the SDK's room list after each sync
- No separate "unread tracking" layer that can drift

### Known Risk: SDK-Level Unread Bugs

It is possible that some of Element X's unread count issues originate in the Rust SDK rather than Element X's UI. Mitigations:
- The SDK adapter layer can implement its own unread tracking (intercept timeline events, compare against read receipts) if SDK counts prove unreliable
- A reconciliation step can compare SDK counts against locally computed counts and log discrepancies
- Self-hosted server with low load allows aggressive read receipt sending

### Background Notifications

Not in PoC scope. Foreground notifications only. Background push (via APNs + sygnal push gateway) is a follow-up that requires running a push gateway alongside the homeserver.

## PoC Scope

### Included in PoC

1. Login screen + session persistence
2. Room list sidebar with collapsible sections and unread badges
3. Timeline view (read messages in a room)
4. Send text messages
5. Create new DMs (start a chat with a Matrix user ID)
6. Cross-signing setup + device verification (SAS emoji flow)
7. Contact verification (SAS from within a DM)
8. Native macOS notifications + dock badge count

### Excluded from PoC (architected for)

- Rich media (images, files) — send and receive
- Reactions
- Message search
- Room creation (groups)
- Room settings / moderation
- Threads
- Voice/video calls
- Spaces
- iOS app target
- Background push notifications

### Post-PoC Priority (user-specified)

1. Reactions
2. Send/receive media
3. Message search
4. Room creation (groups)

## Testing Strategy

### Unit Tests (NebCore)

Test view models and services against mock implementations of the service protocols. Cover:
- State transitions (login flow, verification state machine, room selection)
- Edge cases (network errors, verification timeout, empty room list)
- Unread count computation

### Integration Tests

Small suite hitting a real homeserver with a test account. Validates the SDK adapter works end-to-end. Run manually or in CI, not on every build.

### No UI Tests for PoC

SwiftUI UI testing is fragile and slow. Not worth the investment until the UI stabilizes post-PoC.

## PoC Milestones

Each milestone is a usable checkpoint:

1. **Login** — auth screen, session persistence, logout
2. **Room list** — sidebar with collapsible sections, unread badges
3. **Read messages** — timeline view for a selected room
4. **Send messages** — text composer, send on Enter
5. **New DMs** — create a direct message with a Matrix user ID
6. **Device verification** — cross-signing setup, SAS emoji verification
7. **Contact verification** — SAS verification within DMs
8. **Notifications** — native macOS notifications, dock badge count

After milestone 4, Neb is a basic but functional chat client.
