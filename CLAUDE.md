# Neb -- Native macOS Matrix Client

Neb (named after the Nebuchadnezzar from The Matrix) is a native macOS Matrix client built with SwiftUI and matrix-rust-sdk. ~11,500 lines of Swift across ~70 source files. Targets macOS 14.0+ with Swift 6 strict concurrency.

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
┌─────────────────────────────────────────────────────┐
│  Neb App (SwiftUI)                                  │
│  Views → ViewModels → Service Protocols             │
├─────────────────────────────────────────────────────┤
│  NebCore (Swift Package)                            │
│  Protocols ← Adapters → MatrixRustSDK              │
│                       → NebDatabase (GRDB/SQLite)   │
└─────────────────────────────────────────────────────┘
```

**Key rule:** Views and ViewModels never import MatrixRustSDK. They depend on service protocols only. The adapters are the only code that touches SDK types.

**Dependency flow:** View → ViewModel → ServiceProtocol ← Adapter → MatrixRustSDK + NebDatabase

**Data flow:** SDK events → Adapter writes to database → ViewModel observes database → View renders. The UI reads from the local database, not the SDK's timeline API.

**AppState** (`Neb/AppState.swift`) is the root dependency container -- creates all adapters, wires dependencies via closures, manages login/sync lifecycle.

## Project Structure

```
Neb/                                  # macOS app target
├── NebApp.swift                      # @main entry point
├── AppState.swift                    # Root dependency container (creates all adapters)
├── Neb.entitlements                  # Sandbox + network entitlements
├── ViewModels/
│   ├── LoginViewModel.swift          # Auth state, login/restore/logout
│   ├── RoomListViewModel.swift       # Room list, search, typing indicators, notifications
│   ├── TimelineViewModel.swift       # Messages, composer, editing, reactions, pagination
│   ├── VerificationViewModel.swift   # Device/contact verification state machine
│   └── NewDMViewModel.swift          # New DM creation by Matrix ID
├── Views/
│   ├── LoginView.swift               # Homeserver + credentials form
│   ├── MainView.swift                # NavigationSplitView shell (sidebar + detail)
│   ├── NewDMSheet.swift              # Sheet for creating new DMs
│   ├── Common/
│   │   ├── AvatarView.swift          # Circle avatar with async image + initial fallback
│   │   ├── ConnectionBanner.swift    # "Connecting..." banner when offline
│   │   ├── HTMLRenderCache.swift     # Caches HTML → AttributedString conversions
│   │   ├── EmojiPickerView.swift     # Full emoji picker (9 categories, search)
│   │   └── EmojiData.swift           # Emoji catalog with keywords for search
│   ├── Sidebar/
│   │   ├── SidebarView.swift         # Search bar + DM/Group sections
│   │   └── RoomRowView.swift         # Avatar, name, last message, typing, unread badge
│   ├── Timeline/
│   │   ├── TimelineView.swift        # ScrollView of messages + scroll management
│   │   ├── MessageBubbleView.swift   # Message bubble with reactions, receipts, hover menu
│   │   ├── MessageComposerView.swift # Rich text input + emoji autocomplete + editing
│   │   ├── RichTextEditor.swift      # NSTextView wrapper with formatting support
│   │   ├── FormattingToolbarView.swift # Bold/italic/code/list formatting buttons
│   │   ├── DaySeparatorView.swift    # "Today", "Yesterday", date labels
│   │   ├── ReactionBarView.swift     # FlowLayout of emoji reaction buttons
│   │   ├── ReadReceiptsView.swift    # Overlapping avatar stack (max 3)
│   │   ├── TypingIndicatorView.swift # "X is typing..." with animated dots
│   │   └── QuickReactBar.swift       # Recent emoji + full picker trigger
│   └── Verification/
│       ├── DeviceVerificationView.swift   # SAS emoji flow + recovery key input
│       └── ContactVerificationView.swift  # Verify another user's identity
├── Services/
│   ├── NotificationProtocol.swift    # Notification service protocol
│   └── Notification.swift            # macOS notification + dock badge adapter
└── Utilities/
    ├── HTMLRenderer.swift            # HTML → NSAttributedString → AttributedString
    ├── MarkdownConverter.swift       # NSAttributedString → Markdown for sending
    └── AttributedStringFormatter.swift # Toggle bold/italic/code on NSTextStorage

NebCore/                              # Swift Package (platform-agnostic library)
├── Package.swift                     # swift-tools-version: 6.0
├── Sources/NebCore/
│   ├── Models/
│   │   ├── NebMessage.swift          # Message + SendStatus + ReadReceipt + layout helpers
│   │   ├── NebRoom.swift             # Room metadata (name, avatar, unread, isDirect)
│   │   ├── NebUser.swift             # User (displayName, avatarURL, isVerified)
│   │   ├── NebReaction.swift         # Emoji reaction (count, senderIDs, includesMe)
│   │   ├── NebSession.swift          # Codable session for Keychain persistence
│   │   ├── NebError.swift            # Error enum (notLoggedIn, roomNotFound, recoveryFailed)
│   │   ├── VerificationState.swift   # State machine enum for SAS verification
│   │   ├── AvatarImageCache.swift    # NSCache-based avatar cache (200 items, SDK media API)
│   │   └── UserColorGenerator.swift  # Deterministic color from user ID hash
│   ├── Session/
│   │   ├── AuthProtocol.swift        # login/logout + AuthState enum
│   │   ├── SessionProtocol.swift     # restore, userID, stateStream
│   │   ├── Session.swift             # Adapter: ClientBuilder, crypto store, Keychain
│   │   └── KeychainController.swift  # Keychain read/write for session + passphrase
│   ├── Sync/
│   │   ├── SyncProtocol.swift        # start/stop/statusStream
│   │   └── Sync.swift                # Adapter: sliding sync, room list diffs, member fetch
│   ├── Room/
│   │   ├── TimelineProtocol.swift    # send/edit/delete/react/markAsRead
│   │   ├── RoomsProtocol.swift       # createRoom/DM, roomInfo, roomListStream + TypingProtocol
│   │   ├── MembersProtocol.swift     # members list, invite/kick/ban
│   │   ├── SearchProtocol.swift      # FTS5 search over message bodies
│   │   ├── Room.swift                # Adapter: timeline cache, listeners, message ops
│   │   └── BackfillWorker.swift      # Background pagination of room history
│   ├── Database/
│   │   ├── NebDatabase.swift         # GRDB database: schema, migrations, CRUD, observations
│   │   ├── MessageRecord.swift       # eventID, roomID, senderID, body, timestamp, sendStatus
│   │   ├── MessageWithProfile.swift  # Message joined with sender's displayName + avatarURL
│   │   ├── RoomRecord.swift          # roomID, name, avatarURL, unreadCount, isDirect
│   │   ├── ProfileRecord.swift       # userID, displayName, avatarURL
│   │   ├── ReactionRecord.swift      # eventID, emoji, senderID
│   │   ├── ReadReceiptRecord.swift   # roomID, userID, eventID
│   │   ├── MemberRecord.swift        # roomID, userID, displayName, membership state
│   │   └── BackfillState.swift       # roomID, oldestEventID, reachedStart flag
│   ├── Profile/
│   │   ├── ProfileProtocol.swift     # get/set displayName, avatar
│   │   └── Profile.swift             # Adapter: thin SDK wrapper
│   ├── Privacy/
│   │   ├── PrivacyProtocol.swift     # block/unblock users
│   │   ├── Privacy.swift             # Adapter: SDK ignoreUser/unignoreUser
│   │   ├── SecurityProtocol.swift    # verification, key backup, recovery, identity
│   │   └── Security.swift            # Adapter: SAS verification, backup/recovery listeners
│   └── Devices/
│       ├── DevicesProtocol.swift      # device verification status stream
│       └── Devices.swift             # Adapter: verification state listener
└── Tests/NebCoreTests/
    ├── NebDatabaseTests.swift        # 57 tests: messages, reactions, search, rooms, members
    ├── KeychainControllerTests.swift  # 8 tests: session persistence, multi-user isolation
    └── VerificationStateTests.swift   # 3 tests: terminal states, user actions

project.yml                           # XcodeGen spec → generates Neb.xcodeproj
```

## Build System

- **XcodeGen** generates `Neb.xcodeproj` from `project.yml`. Run `xcodegen generate` after adding/removing files.
- **NebCore** is a local Swift Package imported by the Xcode project.
- **Deployment target:** macOS 14.0 (Sonoma)
- **Swift tools version:** 6.0 (strict concurrency)
- **SDK dependency:** `matrix-rust-components-swift` v26.5.13+ (provides `MatrixRustSDK`)
- **Database dependency:** `GRDB.swift` v7.0.0 (SQLite)
- **Linker flags:** `-Wl,-w` suppresses warnings from SDK binary targeting newer macOS.

## App Lifecycle

`NebApp.swift` is the `@main` entry. It creates one `AppState` and gates the UI:

1. **Splash screen** -- shown while `tryRestoreSession()` checks the Keychain
2. **LoginView** -- shown if no session exists (homeserver URL, username, password)
3. **MainView** -- shown after successful login or session restore

On login, `AppState.onLoggedIn()`:
1. Sets up `AvatarImageCache` with the SDK client
2. Creates `RoomListViewModel`
3. Requests notification permissions
4. Launches sync in a background task
5. When sync comes online: sets up verification listener, starts backfill worker
6. Listens to device verification status stream

On logout: stops backfill, cancels sync, clears `roomListViewModel`.

## View Hierarchy

```
NebApp
└─ WindowGroup
   ├─ Splash (ProgressView while restoring session)
   ├─ LoginView (if logged out)
   │  └─ 3 text fields + login button
   └─ MainView (if logged in)
      ├─ ConnectionBanner ("Connecting..." when offline)
      └─ NavigationSplitView
         ├─ Sidebar: SidebarView
         │  ├─ Search bar (filters rooms by name)
         │  └─ List (two sections: DMs, Groups)
         │     └─ RoomRowView per room
         │        ├─ AvatarView (32pt, color from user ID hash)
         │        ├─ Room name + last message (truncated)
         │        ├─ Typing indicator ("X is typing...")
         │        ├─ Relative timestamp
         │        └─ Unread count badge (blue capsule)
         │
         └─ Detail: TimelineView (or "No Conversation Selected")
            ├─ ScrollView + LazyVStack
            │  ├─ DaySeparatorView (Today, Yesterday, weekday, or date)
            │  └─ MessageBubbleView per message
            │     ├─ Avatar (incoming, non-DM only)
            │     ├─ Bubble (HTML-rendered body + timestamp + edited/status)
            │     ├─ ReactionBarView (FlowLayout of emoji buttons)
            │     ├─ ReadReceiptsView (overlapping avatar stack, max 3)
            │     └─ Hover: smiley → QuickReactBar / EmojiPickerView
            ├─ TypingIndicatorView (animated bouncing dots)
            └─ MessageComposerView
               ├─ Emoji autocomplete (type :query in text)
               ├─ Editing indicator (pencil icon + cancel button)
               ├─ RichTextEditor (NSTextView with formatting)
               │  └─ FormattingToolbarView (popover on text selection)
               └─ Send / submit-edit button

      Sheets:
      ├─ NewDMSheet (create DM by @user:homeserver.com)
      ├─ DeviceVerificationView (SAS emoji comparison or recovery key)
      └─ ContactVerificationView (verify another user)

      Toolbar:
      └─ Device verification badge (green if verified, orange if not)
```

## ViewModels

All are `@Observable @MainActor` (no `@Published`). Located in `Neb/ViewModels/`:

| ViewModel | Drives | Key State | Services |
|-----------|--------|-----------|----------|
| `LoginViewModel` | Login/logout flow | `authState`, `isLoading`, `errorMessage` | `AuthProtocol`, `SessionProtocol` |
| `RoomListViewModel` | Sidebar room list | `allRooms`, `selectedRoom`, `searchQuery`, `roomTypingUsers` | `RoomsProtocol`, `NotificationProtocol` |
| `TimelineViewModel` | Message timeline | `messages`, `messageLayouts`, `typingUsers`, `composerText`, `editingMessage` | `TimelineProtocol`, `TypingProtocol`, `NebDatabase` |
| `VerificationViewModel` | Verification flow | `state: VerificationState` (state machine with timeout) | `SecurityProtocol` |
| `NewDMViewModel` | New DM creation | `userID`, `isCreating`, `errorMessage` | `RoomsProtocol` |

**TimelineViewModel** is the most complex:
- Observes messages from the database via `ValueObservation` (GRDB), not from SDK directly.
- Computes message layouts (grouping from same sender within 5 minutes, day separators).
- Manages typing notices with 5-second debounce.
- Handles message editing (find last outgoing editable message, submit edit via SDK).
- Pagination: starts at 50 messages, loads 50 more on `loadMore()`.

**RoomListViewModel**:
- Subscribes to `roomService.roomListStream()` (which reads from the database).
- Maintains per-room typing subscriptions.
- Posts macOS notifications for new unread messages in non-selected rooms.
- Updates dock badge count.

**VerificationViewModel**:
- Wraps `SecurityProtocol` verification methods.
- 60-second timeout on verification requests.
- State machine: idle → waitingForAcceptance → showingEmoji → confirmed (or failed/timedOut/cancelled).

## Service Protocols and Adapters

Each Matrix domain is abstracted behind a protocol, implemented by an adapter:

| Protocol | Adapter | Module | Responsibility |
|----------|---------|--------|----------------|
| `AuthProtocol` + `SessionProtocol` | `Session` | Session/ | Login, logout, session restore from Keychain |
| `SyncProtocol` | `Sync` | Sync/ | Sliding sync, room list diffs → database |
| `TimelineProtocol` | `Room` | Room/ | Timeline sync, send/edit/delete/react, mark read |
| `RoomsProtocol` + `TypingProtocol` | `Room` | Room/ | Create rooms/DMs, room info, room list stream, typing notices |
| `MembersProtocol` | `Room` | Room/ | Member list, invite/kick/ban |
| `SearchProtocol` | `Room` | Room/ | FTS5 search over message bodies |
| `SecurityProtocol` | `Security` | Privacy/ | E2EE verification, key backup/recovery |
| `DevicesProtocol` | `Devices` | Devices/ | Device verification status stream |
| `ProfileProtocol` | `Profile` | Profile/ | Display name and avatar get/set |
| `PrivacyProtocol` | `Privacy` | Privacy/ | Block/unblock users |
| `NotificationProtocol` | `Notification` | Neb/Services/ | macOS notifications + dock badge (app target only) |

The `Room` adapter is the largest (~732 lines). It manages a **timeline cache** (LRU, 5 entries) so switching rooms doesn't recreate timeline objects. A **generation counter** prevents race conditions on rapid room switches.

### SDK Adapter Example

```swift
// Protocol (in NebCore/Room/)
public protocol TimelineProtocol: Sendable {
    func startTimelineSync(roomID: String) async throws
    func send(roomID: String, body: String) async throws
    func react(roomID: String, eventID: String, emoji: String) async throws
    func markAsRead(roomID: String) async throws
}

// Adapter (in NebCore/Room/)
public final class Room: TimelineProtocol, RoomsProtocol, MembersProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let database: NebDatabase
    // ... wraps MatrixRustSDK calls, writes events to database
}
```

Adapters receive a `() -> Client?` closure to access the logged-in SDK client. This avoids retain cycles and lets adapters work without knowing about AppState.

## Database Layer

`NebDatabase` (GRDB/SQLite) stores everything needed to render the UI offline. The SDK is the sync and network layer; adapters write SDK events to the database; ViewModels observe the database reactively.

### Tables

| Table | PK | Purpose |
|-------|-----|---------|
| `messages` | `eventID` | All messages, with FTS5 full-text index on body |
| `reactions` | `eventID, emoji, senderID` | Emoji reactions per message |
| `read_receipts` | `roomID, userID` | Latest read position per user per room |
| `profiles` | `userID` | Display names and avatar URLs |
| `rooms` | `roomID` | Room metadata (name, avatar, unread count, isDirect) |
| `members` | `roomID, userID` | Room membership (join/invite/leave/ban/knock) |
| `backfill_state` | `roomID` | How far back history has been fetched |
| `dm_assignments` | `directUserID` | Maps user IDs to their DM room IDs |

### Observation Pattern

The UI subscribes to database changes via GRDB `ValueObservation`, not SDK events:

```swift
// NebDatabase
@MainActor
public func observeMessages(roomID: String, limit: Int = 50) -> AsyncStream<[MessageWithProfile]>

@MainActor
public func roomListObservation() -> AsyncStream<[NebRoom]>
```

These emit immediately with current state, then on every database change. This decouples the UI from the SDK and makes it resilient to reconnections.

### Schema Migrations

4 migrations (v1-v4): search index (deprecated) → message database (messages, reactions, receipts, profiles, backfill state) → rooms table → members table.

## Data Flows

### Message Send Lifecycle

1. User types in `RichTextEditor` → `MarkdownConverter` converts `NSAttributedString` to markdown
2. `TimelineViewModel.sendMessage()` → `Room.send()` → SDK queues the message
3. SDK emits timeline diff with `.notSentYet` → `NebTimelineListener` inserts row with transaction ID as PK, `sendStatus: "sending"`
4. Server confirms → SDK promotes to real event ID → listener deletes the transaction row (confirmed message arrives as a separate event)
5. On failure → `.sendingFailed` → listener updates to `sendStatus: "failed"`
6. On app relaunch → `failStalePendingMessages()` marks leftover pending/sending as failed

### Real-Time Streams

All real-time data uses `AsyncStream`:

- **Room list**: `Sync` applies sliding sync diffs → writes `RoomRecord` to DB → `roomListObservation()` emits → `RoomListViewModel.allRooms`
- **Messages**: `NebTimelineListener` processes timeline diffs → writes `MessageRecord` to DB → `observeMessages()` emits → `TimelineViewModel.messages`
- **Typing**: SDK `TypingNotificationsListener` → `NebTypingListener` resolves user info → `typingUsersStream()` → `TimelineViewModel.typingUsers`
- **Verification**: `VerificationDelegateImpl` wraps SDK delegate → `verificationStateStream()` → `VerificationViewModel.state`
- **Online status**: `Sync.statusStream()` → `AppState.isOnline` → `ConnectionBanner`
- **Device verification**: `DeviceVerificationStateListenerImpl` → `verificationStatusStream()` → `AppState.deviceVerificationStatus` → toolbar badge

### Room Selection

When the user selects a room in the sidebar:
1. `MainView.onChange(of: selectedRoom?.id)` fires
2. Creates a new `TimelineViewModel` with the room's services and initial unread count
3. `TimelineViewModel` calls `startTimelineSync()` on the adapter
4. Adapter gets/creates timeline from the LRU cache, attaches a `NebTimelineListener`
5. Listener writes events to the database as they arrive
6. `TimelineViewModel` observes `database.observeMessages(roomID:)` and renders

## Background Processing

### BackfillWorker

Paginates room history backwards to fill the local database:
- Triggered after sync comes online
- Iterates all rooms, 50 events at a time, up to 200 batches (10k events) per room
- Tracks progress in `backfill_state` table (resumes across app launches)
- `prioritize(roomID:)` reorders the queue when user opens a room
- Has its own `BackfillTimelineListener` that writes directly to the database

### Sync Retry

Exponential backoff on connection failure: 2, 4, 8, 16, 32, 30 (capped) seconds.

## SDK Listener Retention

SDK listener objects from the Rust FFI **must** be retained as instance properties. If they're local variables, Rust deallocates them and the app crashes. Every adapter stores its listeners:

| Listener | File | Retained In |
|----------|------|-------------|
| `NebRoomListEntriesListener` | Sync.swift | `Sync.entriesListener` |
| `NebTimelineListener` | Room.swift | `TimelineHandle.listener` |
| `BackfillTimelineListener` | BackfillWorker.swift | local task scope |
| `NebTypingListener` | Room.swift | closure scope |
| `VerificationDelegateImpl` | Security.swift | `Security.delegate` |
| `BackupStateListenerImpl` | Security.swift | `Security.backupStateListenerImpl` |
| `RecoveryStateListenerImpl` | Security.swift | `Security.recoveryStateListenerImpl` |
| `DeviceVerificationStateListenerImpl` | Devices.swift | `Devices.verificationStateListener` |

`TaskHandle` objects returned by listener registration are also retained.

## Concurrency Patterns

- ViewModels: `@Observable @MainActor` (no `@Published`)
- Adapters: `@unchecked Sendable` (SDK objects aren't natively Sendable)
- Mutable state in listeners: `nonisolated(unsafe)` for Swift 6 compatibility
- Background tasks: `@ObservationIgnored nonisolated(unsafe) var task: Task<Void, Never>?`
- `deinit` cancels tasks to prevent leaks

## Testing

Tests use Swift Testing framework (`@Test`, `#expect`). Run from NebCore directory:

```bash
cd NebCore && swift test
```

68 tests total:
- **NebDatabaseTests** (57) -- message CRUD, reactions, FTS search, rooms, members, ordering, redaction, pending lifecycle
- **KeychainControllerTests** (8) -- session/passphrase persistence, multi-user isolation
- **VerificationStateTests** (3) -- terminal states, user action strings

## Logging

Uses `os.Logger` with subsystem `"com.neb.app"` and per-module categories:
- `AppState` -- post-login wiring, sync lifecycle
- `Session` -- login, session restore, logout
- `Sync` -- room list updates, sync service state
- `Room` -- timeline events, message operations
- `Keychain` -- session storage
- `Database` -- DB errors
- `Security` -- verification flow, key recovery
- `Devices` -- device status
- `Backfill` -- backfill worker progress
- `Profile`, `Privacy` -- domain-specific logs

## Session Persistence

Session data stored in the app sandbox at `~/Library/Containers/com.neb.app/Data/Library/Application Support/Neb/`:

| Path | Purpose | Cleared on login? | Cleared on logout? |
|------|---------|-------------------|-------------------|
| Keychain entry | Access token, user/device ID, homeserver URL | Overwritten | Yes |
| `data/` | SDK state + crypto SQLite (device keys, cross-signing) | No (reused) | Yes |
| `cache/` | SDK media + event cache | No | Yes |

Preserving `data/` across logins avoids the 1-2 minute cross-signing key upload on subsequent logins. On login only the Keychain entry is overwritten. On logout everything is cleared.

## Known Quirks

- **Homeserver URL hardcoded** in `AppState.homeserverURL` as `"https://matrix.matto.io"`. Used for avatar image loading via the SDK's media API. Should be extracted from the stored session.
- **Cross-signing on login** -- `autoEnableCrossSigning` and `autoEnableBackups` are enabled on the ClientBuilder. First login with a fresh crypto store can take 1-2 minutes. Subsequent logins reuse the crypto store and are fast. Do NOT clear the `data/` directory on login -- only clear the Keychain entry.
- **Sliding sync** -- uses `.discoverNative`. The homeserver must support native sliding sync. Room list entries require `setFilter(kind: .all(filters: []))` to start flowing.
- **Room subscription** -- rooms must be explicitly subscribed via `roomListService.subscribeToRooms()` before their timeline delivers events.
- **Debounced room list** -- room list updates are debounced (100ms) to avoid redundant async room info fetches from rapid SDK diff callbacks.
- **Avatar loading** -- uses SDK's `client.getMediaThumbnail()` for authenticated media access, not raw HTTP. Cached in `AvatarImageCache` (NSCache, in-memory only, 200 items).
- **Contact verification** -- cannot re-verify an already-verified user (SDK throws "User is already verified"). Device verification can be re-done.
- **Unencrypted messages** -- show "Encrypted message (verify this device to decrypt)" placeholder.
- **Linker warnings** -- suppressed with `-Wl,-w` in project.yml. SDK binary targets macOS 26.4 while we target 14.0.

## Not Yet Implemented

- `sendImage()`, `sendFile()`, `sendVideo()` -- protocol methods exist but are empty stubs
- Image/file attachment rendering in the timeline
- Room settings UI (name/topic/avatar editing)
- Member list UI (protocols exist, no view)
- Search UI (protocol and FTS exist, no view)
- User profile editing UI (protocol exists, no view)
- Block/unblock UI (protocol exists, no view)
- Invite handling UI

## Entitlements

The app is sandboxed (`com.apple.security.app-sandbox`) with network client access (`com.apple.security.network.client`). These are in `Neb/Neb.entitlements` and referenced in `project.yml`.
