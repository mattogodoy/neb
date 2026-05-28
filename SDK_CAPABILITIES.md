# Matrix Rust SDK Capabilities Analysis

**SDK Version:** matrix-rust-components-swift v26.5.13  
**Analyzed from:** Neb codebase integration + SDK source inspection

## Executive Summary

The Matrix Rust SDK provides a comprehensive client library for Matrix protocol support. Neb currently uses ~15% of available functionality, focusing on core messaging features. The SDK offers extensive capabilities for advanced features that remain untapped.

---

## CURRENTLY USED BY NEB

### 1. Authentication & Session (5 methods)
- `Client.login(username, password, initialDeviceName, deviceId)` - password login
- `Client.restoreSession(session)` - resume previous session
- `Client.logout()` - sign out
- `Client.userId()` - get current user ID
- `Client.session()` - get session data
- `ClientBuilder` with configuration chain

### 2. Sync & Room List (7 methods)
- `SyncService.start()` - begin background sync
- `SyncService.stop()` - stop syncing
- `SyncService.roomListService()` - get room list manager
- `RoomListService.allRooms()` - get all rooms
- `RoomListService.subscribeToRooms(roomIds)` - subscribe to specific rooms
- `RoomList.entriesWithDynamicAdapters()` - streaming room updates
- `RoomListDynamicEntriesController.setFilter()` - filter rooms

### 3. Room Operations (8 methods)
- `Client.getRoom(roomId)` - fetch room
- `Client.getDmRoom(userId)` - find DM room
- `Client.createRoom(parameters)` - create new room
- `Room.id()` - get room ID
- `Room.displayName()` - computed room name
- `Room.roomInfo()` - room metadata
- `Room.membersNoSync()` - paginated member list
- `Room.markAsRead(receiptType)` - send read receipt

### 4. Timeline & Messages (10 methods)
- `Room.timeline()` - get message timeline
- `Timeline.send(msg)` - send message
- `Timeline.edit(itemId, newContent)` - edit message
- `Timeline.toggleReaction(itemId, emoji)` - add/remove emoji
- `Timeline.paginateBackwards(numEvents)` - load older messages
- `Timeline.addListener(listener)` - attach update listener
- `messageEventContentFromMarkdown(md)` - create formatted message
- Message properties: body, isEdited, timestamp, sender, readReceipts, reactions

### 5. Encryption & Verification (12 methods)
- `Encryption.verificationState()` - device verification status
- `Encryption.verificationStateListener()` - listen to verification changes
- `Encryption.userIdentity(userId)` - check user verification
- `Encryption.backupExistsOnServer()` - key backup present
- `Encryption.recoverAndFixBackup(recoveryKey)` - restore from backup
- `Encryption.waitForE2eeInitializationTasks()` - wait for crypto setup
- `SessionVerificationController.requestDeviceVerification()`
- `SessionVerificationController.requestUserVerification(userId)`
- `SessionVerificationController.acceptVerificationRequest()`
- `SessionVerificationController.startSasVerification()` - emoji matching
- `SessionVerificationController.approveVerification()` - confirm
- `SessionVerificationController.cancelVerification()` - abort

### 6. Typing Notifications (3 methods)
- `Room.typingNotice(isTyping)` - send typing indicator
- `Room.subscribeToTypingNotifications(listener)` - listen for typists
- `TypingNotificationsListener.call(typingUserIds)` - receive updates

**Total Methods Used: ~45 out of ~500+ available**

---

## NOT USED - AVAILABLE FEATURES

### Room State & Management (25+ methods)
Query and modify room properties:
- Aliases: `canonicalAlias()`, `alternativeAliases()`, set/unset
- Settings: `topic()`, `guestAccess()`, `joinRule()`, `historyVisibility()`, `encryption()`
- Modifications: `setName()`, `setTopic()`, `setAvatar()`, `setJoinRule()`, `setHistoryVisibility()`, `setPowerLevels()`
- Members: `membersCount()`, `activeMembersCount()`, `cachedMembers()`, `updateMembers()`
- Actions: `invite(userId)`, `kick(userId)`, `ban(userId)`, `unban(userId)`

### Rich Messages (20+ types)
- **Files**: images, videos, audio, documents (with captions, thumbnails)
- **Location**: location sharing, live location updates
- **Polls**: create polls, send answers
- **Replies**: reply to specific messages, create threads
- **Redaction**: delete messages
- **Forwarding**: forward messages
- **Stickers**: sticker sending

### Media Management
- `Client.getMediaThumbnail()` - fetch cached thumbnails
- `Room.sendAttachment()` - upload files
- Media upload progress tracking
- Event cache configuration
- Crypto store management

### Search Capabilities
- `GlobalSearchIterator` - full-text search across all rooms
- `RoomDirectorySearch` - discover public rooms on homeserver
- Search filters, pagination, ranking

### Account Management
- Profile: `setDisplayName()`, `uploadAvatar()`, `profile()`
- Presence: `sendPresence()`, `PresenceListener` - online status
- Device management: list devices, rename, delete
- Account data: custom storage (listeners, reading, writing)
- Homeserver capabilities discovery

### Advanced Encryption
- Device list management with signing
- Key backup: enable/disable, generate recovery keys
- Secret storage for cross-signing secrets
- Cross-signing verification chain
- Automatic key requests for encrypted messages
- QR code verification
- Recovery codes (backup codes)
- Out-of-band device verification

### VoIP & Calls
- `CallDeclineListener` - incoming call notifications
- VoIP signaling and state management
- Call participants tracking
- Call room integration

### Spaces
- Space hierarchy management
- Space rules and child relationships
- `LeaveSpaceHandle` - space operations
- Knock request handling

### Push Notifications
- `NotificationClient` - server-side push configuration
- `NotificationSettings` - mention/keyword rules
- `PushRule`, `PushCondition` - notification filters
- VoIP push notifications

### Timeline Advanced Features
- `paginateForwards()` - load newer messages
- `focusedEventId` - jump to event
- `canRewind` / `canForwardPaginate` - state queries
- `addReaction()` / `removeReaction()` - explicit reaction control
- `redact(itemId)` - delete message
- `sendReply()`, `sendInThread()` - threaded messages
- `getInThreadTimeline()` - load thread
- Day separator items, loading indicators
- `LazyTimelineItemProvider` - lazy timeline loading

### Authentication Alternatives
- QR code login
- OIDC/OAuth flows
- SSO/SAML support
- `HomeserverLoginDetails` - server capabilities

### Drafts
- `ComposerDraftType` - save message drafts
- `DraftAttachment` - draft media
- Draft persistence

---

## SDK ARCHITECTURE

### Core Types

**Client** (main entry point)
- Authentication, room access, encryption
- Session and profile management
- Media operations
- Search and directory

**Room** (room context)
- Timeline access
- Member operations
- State queries and modifications
- Notifications, typing

**Timeline** (message stream)
- Send/edit/react/paginate
- Real-time listeners
- Local echo handling
- Event history

**Encryption** (crypto operations)
- Verification flows
- Key backup/recovery
- Device management
- Cross-signing

**SyncService** (background sync)
- Maintains room list
- Updates read receipts, typing
- Manages crypto state
- Handles reconnection

---

## UNTAPPED OPPORTUNITIES

### Quick Wins (1-2 weeks each)
1. **Message search** - full-text search within rooms
2. **Room info view** - display topic, members, settings
3. **Presence indicator** - show online status
4. **Message deletion** - redact messages

### Medium Effort (2-4 weeks each)
1. **File uploads** - images, videos, documents
2. **Room settings** - edit topic, avatar, name
3. **Member management** - invite, kick, ban operations
4. **Message replies** - threaded conversation support
5. **Account profile** - edit display name, avatar

### Larger Features (4+ weeks each)
1. **Search UI** - discover rooms, search messages
2. **Voice calls** - VoIP signaling and UI
3. **Spaces** - hierarchical room organization
4. **Polls** - voting in messages
5. **Location sharing** - live location updates
6. **Device management** - security & session control

---

## PERFORMANCE NOTES

From CLAUDE.md insights:
- Sliding sync requires `.discoverNative` support
- Room subscription must happen before timeline delivers events
- SDK listeners must be retained as instance properties (else crash)
- First login with crypto: 1-2 minutes (crypto initialization)
- Session restore with cached crypto: ~seconds
- Room list updates are debounced (100ms) to avoid redundant fetches
- Avatar loading uses SDK's authenticated media API, cached in-memory

---

## WHAT TO READ NEXT

1. **SDK FFI bindings**: `/NebCore/.build/checkouts/matrix-rust-components-swift/Sources/MatrixRustSDK/matrix_sdk_ffi.swift` (54k lines - generated)
2. **SDK Examples**: `/NebCore/.build/checkouts/matrix-rust-components-swift/Examples/Walkthrough.swift`
3. **Official SDK Docs**: https://github.com/matrix-org/matrix-rust-sdk (Rust implementation)
4. **Matrix Spec**: https://spec.matrix.org/latest/

---

## Adapter Files Reference

| Adapter | Implements | SDK Types |
|---------|-----------|-----------|
| MatrixAuthAdapter | AuthServiceProtocol | Client, ClientBuilder, Session |
| MatrixSyncAdapter | SyncServiceProtocol | SyncService, RoomListService, RoomList, Room |
| MatrixRoomAdapter | RoomServiceProtocol | Room, Timeline, TimelineItem, Event, Reactions |
| MatrixCryptoAdapter | CryptoServiceProtocol | Encryption, SessionVerificationController, UserIdentity |
| MatrixTypingAdapter | TypingServiceProtocol | Room, TypingNotificationsListener |
| MatrixNotificationAdapter | NotificationServiceProtocol | UNUserNotificationCenter (native, not SDK) |

