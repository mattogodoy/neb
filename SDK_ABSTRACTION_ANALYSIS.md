# Neb: MatrixRustSDK vs NebCore Abstraction Layer Comparison

## Executive Summary

NebCore provides a clean abstraction layer over MatrixRustSDK with 6 service protocols and 5 data models. The adapters do significant transformation work:

- **SDK types are largely hidden** — views never see SDK objects
- **Lossy conversions** — some SDK data is deliberately discarded (unread notification type, media URLs, etc.)
- **Selective exposure** — many SDK features are not exposed at all (user account info, room state, direct message handling details)
- **Stream-based async** — all continuous operations use `AsyncStream` rather than listeners (one layer of abstraction)

---

## 1. PROTOCOL ANALYSIS: What NebCore Exposes

### AuthServiceProtocol

**Methods:**
1. `login(homeserverURL, username, password) async throws`
2. `restoreSession() async throws -> Bool`
3. `logout() async throws`
4. `authState: AuthState { get async }`
5. `authStateStream() -> AsyncStream<AuthState>`

**SDK Methods Called (MatrixAuthAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `login()` | `ClientBuilder().serverNameOrHomeserverUrl()` | Client builder | — | — |
| | `.sessionPaths(dataPath, cachePath)` | — | — | — |
| | `.slidingSyncVersionBuilder(.discoverNative)` | — | — | — |
| | `.autoEnableCrossSigning(true)` | — | — | — |
| | `.autoEnableBackups(true)` | — | — | — |
| | `.build()` | `Client` | — | `Client` kept private |
| | `client.login(username, password, ...)` | Success or error | `Void` | Login response details |
| | `client.userId()` | `String` (userID) | Used in state only | — |
| `restoreSession()` | `ClientBuilder()` ... `.build()` | `Client` | — | — |
| | `client.restoreSession(session)` | Success or error | `Bool` | Restore status details |
| | `client.userId()` | `String` | Used in state only | — |
| `logout()` | `client.logout()` | Void | `Void` | — |
| | File deletion | — | — | — |
| `authState` | Direct property access | `AuthState` enum | `AuthState` enum | — |
| `authStateStream()` | Manual continuation | `AsyncStream<AuthState>` | `AsyncStream<AuthState>` | — |

**Key SDK Capabilities NOT Exposed:**
- Device ID assignment/management
- Session data (device name, encryption keys)
- User profile (displayName, avatarURL, initial_device_display_name)
- Login flow stages (if homeserver requires 2FA/CAPTCHA)
- Sync version discovery details
- Cross-signing setup status
- Backup setup status

**Key SDK Data Lost in Translation:**
- `client.login()` response details
- `client.restoreSession()` error details vs success details

---

### SyncServiceProtocol

**Methods:**
1. `startSync() async throws`
2. `stopSync() async throws`
3. `roomListStream() -> AsyncStream<[NebRoom]>`

**SDK Methods Called (MatrixSyncAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `startSync()` | `client.syncService()` | `SyncService` builder | — | SyncService kept private |
| | `.finish()` | `SyncService` | — | — |
| | `sync.roomListService()` | `RoomListService` | — | Kept as private property |
| | `roomList.allRooms()` | `RoomList` | — | Kept as private property |
| | `allRooms.entriesWithDynamicAdapters()` | Listener + Controller | — | Kept for internal use |
| | `controller.setFilter(kind: .all(filters: []))` | Filter applied | — | — |
| | `sync.start()` | Starts sync loop | `Void` | Sync state/progress |
| `stopSync()` | `syncService?.stop()` | Stops sync loop | `Void` | Sync state |
| `roomListStream()` | Manual continuation emission | `AsyncStream<[NebRoom]>` | `AsyncStream<[NebRoom]>` | — |

**Room List Entry Conversion (RoomListEntriesListener):**

Each `Room` SDK object is converted to `NebRoom`:
```
Room (SDK) → room.id() → NebRoom.id
           → room.displayName() → NebRoom.name
           → room.roomInfo() → { isDirect, numUnreadMessages, avatarUrl }
           → room.membersNoSync() → directUserID (for DMs)
```

**Key SDK Capabilities NOT Exposed:**
- Full sync state (timeline cursors, account data)
- Sync loop timing/progress
- Room list filtering beyond `.all(filters: [])`
- Sliding sync subscriptions management
- Room list pagination details
- Notification counts (separate from unread)

**Key SDK Data Lost:**
- `room.roomInfo().numUnreadNotifications` (vs numUnreadMessages) — uses `max(both)`
- Room topic/description
- Room avatar fallback strategy (member avatar used but not stored as policy)
- Historical unread counts
- Room join rules, guest access, encryption settings
- Power levels, tombstone state

---

### RoomServiceProtocol

**Methods:**
1. `timelineStream(roomID: String) -> AsyncStream<[NebMessage]>`
2. `sendMessage(roomID: String, body: String) async throws`
3. `sendReadReceipt(roomID: String, eventID: String) async throws`
4. `createDM(userID: String) async throws -> String`
5. `paginateBackwards(roomID: String, count: UInt) async throws`
6. `toggleReaction(roomID: String, eventID: String, emoji: String) async throws`
7. `editMessage(roomID: String, eventID: String, newBody: String) async throws`

**SDK Methods Called (MatrixRoomAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `timelineStream()` | `rls.subscribeToRooms([roomID])` | Subscription | — | Subscription status |
| | `client.getRoom(roomId)` | `Room \| nil` | — | Room kept private |
| | `room.timeline()` | `Timeline` | — | Timeline kept private |
| | `room.membersNoSync()` | `PaginableList<RoomMember>` | — | Used only for profile cache |
| | `timeline.addListener(listener)` | `TaskHandle` | — | Handle kept to retain listener |
| | `timeline.paginateBackwards(numEvents: 50)` | Paginated items | Merged into stream | — |
| `sendMessage()` | `messageEventContentFromMarkdown(body)` | `MessageEventContent` | — | — |
| | `timeline.send(content)` | `TaskHandle` | `Void` | Send state/progress |
| `sendReadReceipt()` | `room.markAsRead(receiptType: .read)` | Read receipts sent | `Void` | Receipt details |
| `createDM()` | `client.getDmRoom(userId)` | `Room \| nil` | Room ID or create | — |
| | `client.createRoom(params)` | Room ID | Room ID | Creation details |
| `paginateBackwards()` | `timeline.paginateBackwards(count)` | Paginated items | Merged into stream | — |
| `toggleReaction()` | `timeline.toggleReaction(itemId, key)` | Reaction toggled | `Void` | Toggle state/result |
| `editMessage()` | `timeline.edit(itemId, newContent)` | Edited event | Merged into stream | Edit state/result |

**Timeline Item Conversion (NebTimelineListener):**

Each `TimelineItem` → `NebMessage`:
```
TimelineItem (SDK)
  → .asEvent()? (filters out virtual items like day separators)
    → event.eventOrTransactionId → NebMessage.id
    → event.sender → NebMessage.senderID
    → event.senderProfile → NebMessage.senderDisplayName/senderAvatarURL
    → event.timestamp → NebMessage.timestamp (ms→s conversion)
    → event.localSendState → NebMessage.sendStatus
    → msgLike.kind.message → NebMessage.body/formattedBody/isEdited
    → msgLike.kind.unableToDecrypt → Body: "🔒 Encrypted..."
    → msgLike.reactions → [NebReaction]
    → event.readReceipts → [ReadReceipt]
    → event.isOwn, event.isEditable → NebMessage.isOutgoing, isEditable
```

**Key SDK Capabilities NOT Exposed:**
- Event types beyond messages (call invites, joins/leaves, etc.)
- Message reactions beyond aggregated emoji
- Read receipt types (full read vs just read)
- Message search
- Threading/replies
- Message redactions
- Custom event content/state events
- Timeline pagination control (start point, direction limits)
- Event encryption status details
- Attachment handling (images, files, URLs)

**Key SDK Data Lost:**
- Full `MessageEventContent` — only `body` + `formattedBody` exposed
- `TimelineItem` virtual items (day separators, etc.)
- Event relations (replies, edits, reactions as separate payloads)
- Sender profile cache timing/refresh
- Send state progression (notSentYet → sending → sent/failed)
- Formatted body format type (HTML/Markdown) — assumed HTML
- Message type beyond text (m.emote, etc.)
- Unread thread status

---

### CryptoServiceProtocol

**Methods:**
1. `startDeviceVerification() async throws`
2. `startUserVerification(userID: String) async throws`
3. `acceptVerification() async throws`
4. `confirmEmoji() async throws`
5. `declineEmoji() async throws`
6. `cancelVerification() async throws`
7. `verificationStateStream() -> AsyncStream<VerificationState>`
8. `deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus>`
9. `isUserVerified(userID: String) async -> Bool`
10. `hasKeyBackup() async throws -> Bool`
11. `recoverKeys(recoveryKey: String) async throws`

**SDK Methods Called (MatrixCryptoAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `startDeviceVerification()` | `client.getSessionVerificationController()` | `SessionVerificationController` | — | Controller kept private |
| | `controller.requestDeviceVerification()` | Verification started | `Void` | Request ID, flow state |
| `startUserVerification()` | `controller.requestUserVerification(userId)` | Verification started | `Void` | Request details, flow ID |
| `acceptVerification()` | `controller.acknowledgeVerificationRequest()` | Acknowledged | `Void` | Ack state |
| | `controller.acceptVerificationRequest()` | Accepted | `Void` | — |
| | `controller.startSasVerification()` | SAS started | `Void` | SAS details |
| `confirmEmoji()` | `controller.approveVerification()` | Approved | `Void` | — |
| `declineEmoji()` | `controller.declineVerification()` | Declined | `Void` | — |
| `cancelVerification()` | `controller.cancelVerification()` | Cancelled | `Void` | Cancel reason |
| `verificationStateStream()` | `SessionVerificationControllerDelegate` callback | State changes | `AsyncStream<VerificationState>` | — |
| `deviceVerificationStatusStream()` | `encryption.verificationState()` | Initial state | `AsyncStream<DeviceVerificationStatus>` | — |
| | `encryption.verificationStateListener()` | State changes | Mapped to enum | — |
| `isUserVerified()` | `encryption.userIdentity(userId, fallbackToServer: false)` | `UserIdentity \| nil` | `Bool` | Identity details |
| | `identity.isVerified()` | `Bool` | `Bool` | — |
| `hasKeyBackup()` | `encryption.backupExistsOnServer()` | `Bool` | `Bool` | Backup details |
| `recoverKeys()` | `encryption.recoverAndFixBackup(recoveryKey)` | Keys recovered | `Void` | Recovery progress |
| | `encryption.waitForE2eeInitializationTasks()` | E2EE ready | `Void` | — |

**Verification State Mapping (VerificationDelegate):**

```
SessionVerificationData (SDK)
  → .emojis(values, _) → VerificationState.showingEmoji([VerificationEmoji])
  → .decimals(values) → VerificationState.showingEmoji([single "Decimal verification" item])

SessionVerificationControllerDelegate callbacks:
  → didReceiveVerificationRequest() → .requested
  → didAcceptVerificationRequest() → (internal: starts SAS)
  → didStartSasVerification() → (waits for data)
  → didReceiveVerificationData() → .showingEmoji or .showingEmoji(decimals)
  → didFail() → .failed(reason: "Verification failed")
  → didCancel() → .cancelled
  → didFinish() → .confirmed
```

**Key SDK Capabilities NOT Exposed:**
- QR code verification (Qr enum in SessionVerificationData)
- Decimal verification (exposed as text, not structured data)
- Verification flow IDs/transaction IDs
- Incoming verification request details (sender profile)
- Cross-signing status details
- Device key data
- Backup recovery codes
- Secret sharing (passphrase setup, recovery key generation)
- User identity data (keys, signatures, trust state)

**Key SDK Data Lost:**
- `SessionVerificationData.Qr` — QR code verification not supported
- `SessionVerificationRequestDetails` — incoming request details discarded
- Recovery error details mapped to generic strings
- `UserIdentity` — only `isVerified()` boolean exposed
- Backup state beyond existence
- E2EE initialization task progress

---

### TypingServiceProtocol

**Methods:**
1. `sendTypingNotice(roomID: String, isTyping: Bool) async throws`
2. `typingUsersStream(roomID: String) -> AsyncStream<[NebUser]>`

**SDK Methods Called (MatrixTypingAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `sendTypingNotice()` | `client.getRoom(roomId)` | `Room \| nil` | — | — |
| | `room.typingNotice(isTyping)` | Notice sent | `Void` | Send state |
| `typingUsersStream()` | `room.subscribeToTypingNotifications(listener)` | Listener handle | — | Handle kept to retain listener |
| | (in listener) `room.membersNoSync()` | Member list | Used for profiles | — |

**Typing Notification Processing:**

```
TypingNotificationsListener callback
  → typingUserIds: [String]
    → for each userID:
      → room.membersNoSync() → find member → extract displayName, avatarUrl
      → NebUser(id, displayName, avatarURL, isVerified: false)
    → AsyncStream<[NebUser]>
```

**Key SDK Capabilities NOT Exposed:**
- Raw user IDs (always enriched with display names)
- Typing timeout details
- Multiple typing notifications per user

**Key SDK Data Lost:**
- Typing timeout (fixed in SDK)
- User verification status (hardcoded to false)
- Member lookup failure handling (silently skips)

---

### NotificationServiceProtocol

**Methods:**
1. `requestPermission() async throws -> Bool`
2. `postNotification(title: String, body: String, roomID: String) async`
3. `updateBadgeCount(_ count: UInt) async`

**SDK Methods Called (MatrixNotificationAdapter):**

| Protocol Method | SDK Call | SDK Returns | NebCore Returns | Data Lost |
|---|---|---|---|---|
| `requestPermission()` | `UNUserNotificationCenter.requestAuthorization()` | `Bool` | `Bool` | — |
| `postNotification()` | `UNNotificationRequest()` | — | — | — |
| | `UNUserNotificationCenter.add()` | Notification posted | `Void` | Post state |
| `updateBadgeCount()` | `UNUserNotificationCenter.setBadgeCount()` | Badge updated | `Void` | — |
| | `NSApplication.dockTile.badgeLabel` | Dock badge set | `Void` | — |

**Key SDK Capabilities NOT USED:**
- This adapter uses **zero** MatrixRustSDK code
- Pure native macOS/iOS notifications
- No SDK notification handling

---

## 2. MODEL ANALYSIS: What Data is Stored

### NebRoom

**Fields (9 total):**

| Field | Type | SDK Source | Transformations | Data Lost |
|---|---|---|---|---|
| `id` | String | `room.id()` | Direct | — |
| `name` | String | `room.displayName() ?? roomID` | Fallback to ID | Room name synthesis rules (member names for DMs) |
| `avatarURL` | String? | `room.roomInfo().avatarUrl` | Direct | Avatar fallback chain (member avatar used but not stored) |
| `lastMessage` | String? | Not set | Always nil | `room.lastRoomEventBuilder()` — no timeline access |
| `lastMessageTimestamp` | Date? | Not set | Always nil | — |
| `unreadCount` | UInt | `max(info.numUnreadMessages, info.numUnreadNotifications)` | Max operation | Notification type distinction lost, unread highlight type |
| `isDirect` | Bool | `room.roomInfo().isDirect` | Direct | DM room type details |
| `directUserID` | String? | `room.membersNoSync()` filter | Manual extraction | Other member IDs (group DM scenario) |
| `memberCount` | UInt | Not set | Always 0 | `room.memberCount()` — deliberately not called |

**SDK Data Available but NOT Mapped:**
- `room.roomInfo()`:
  - `canonicalAlias` — room address
  - `numUnreadHighlights` — distinct from unread
  - `joinRule` — public/invite/knock/private
  - `guestAccess` — whether guests can join
  - `historyVisibility` — who can read past messages
  - `encryption` — encryption algorithm
  - `topic` — room description
  - `heroId` — fallback member for room name
  - `state` — full state snapshot
  - `isEncrypted` — boolean flag
  - `creatorUserId` — who created room
  - `powerLevels` — user permissions
  - `tombstoneState` — if room is dead
- `room.memberCount()` — exists but never called
- `room.isFavourite()` — favorite status
- `room.joinedMembersCount()` — actual joined members
- `room.activeMembersCount()` — recently active count
- `room.isBanned()` — user's ban status
- `room.knownDisplayName()` — alternative display name

---

### NebMessage

**Fields (15 total):**

| Field | Type | SDK Source | Transformations | Data Lost |
|---|---|---|---|---|
| `id` | String | `event.eventOrTransactionId` | `.eventId \| .transactionId` → unwrap | — |
| `roomID` | String | Provided | Direct | — |
| `senderID` | String | `event.sender` | Direct | — |
| `senderDisplayName` | String | `event.senderProfile` case | Fallback to sender ID | Profile cache lag |
| `senderAvatarURL` | String? | `event.senderProfile` case | Direct | Profile cache lag |
| `body` | String | `msgContent.body` | Direct (text messages) | For `unableToDecrypt`: "🔒 Encrypted..." |
| `formattedBody` | String? | `textContent.formatted.body` | Direct if `.html` | Only HTML format; Markdown format discarded |
| `timestamp` | Date | `event.timestamp` | ms → s conversion | — |
| `isOutgoing` | Bool | `event.isOwn` | Direct | — |
| `sendStatus` | SendStatus | `event.localSendState` | `notSentYet→sending, failed→failed, sent→sent` | State details (failure reasons) |
| `readReceipts` | [ReadReceipt] | `event.readReceipts` | Filter out self, map profiles | Full receipt data (timestamps) |
| `reactions` | [NebReaction] | `msgLike.reactions` | Aggregated by emoji | Reaction timestamps, reacted-on user ID |
| `isEdited` | Bool | `msgContent.isEdited` | Direct | Edit history (not preserved) |
| `isEditable` | Bool | `event.isEditable && event.isOwn` | Direct | Edit permissions detail |

**SDK Data Available but NOT Mapped:**
- `TimelineItem` variants:
  - Virtual items (day separators, loading states) — filtered out entirely
  - State events (join/leave, topic change, etc.) — not exposed
- `event.content` types:
  - Non-message content (call invites, custom events) — filtered out
  - `m.emote` — reaction/action content treated as nil
  - `m.image, m.file, m.audio, m.video` — media types not exposed
- `MessageEventContent`:
  - `inReplyTo()` — threading/replies
  - `editedEventId()` — edit chain
  - `relates_to` — all relation types beyond reactions
  - `m.new_content` — edit payloads
- `msgLike.reactions`:
  - Reaction timestamps
  - Per-sender reaction data (not aggregated)
  - Reaction content type
- `event` properties:
  - `decryptionError` — why decryption failed
  - `hasFailedDecryption()` — encryption failure details
  - `withheldDecryptionReason()— withholding reason
  - `isThreadMessage()` — threading info
  - `threadRootId()` — thread parent
  - Full event JSON (for custom extensions)
- `SenderProfile`:
  - Cache state (loading, ready, error) — only `.ready` used

---

### NebUser

**Fields (4 total):**

| Field | Type | SDK Source | Transformations | Data Lost |
|---|---|---|---|---|
| `id` | String | Direct | Direct | — |
| `displayName` | String? | `member.displayName` or cache | Direct | Display name fallback rules |
| `avatarURL` | String? | `member.avatarUrl` or cache | Direct | Avatar URL fallback chain |
| `isVerified` | Bool | (always false in typing) | Hardcoded false | User verification status not queried |

**SDK Data Available but NOT Mapped:**
- `RoomMember`:
  - `membership` — join/invite/leave/ban (used for filtering only)
  - `joinedAtMs` — join timestamp
  - `lastSeenAtMs` — activity timestamp
  - `powerLevel` — user permissions in room
  - `role` — computed from power levels
- `UserIdentity` (from crypto):
  - `userId` — direct ID
  - `isVerified()` — cross-signing status
  - `isSelfSigned()` — verified by self
  - `userSigningKeys()` — full key data
  - `masterKeys()` — master key data
  - `selfSigningKeys()` — self-signing key data

**Verification Status NOT Exposed:**
- Always hardcoded to `false` in TypingAdapter
- Would require `cryptoService.isUserVerified()` call per user
- Not cached or batched

---

### NebReaction

**Fields (4 total):**

| Field | Type | SDK Source | Transformations | Data Lost |
|---|---|---|---|---|
| `emoji` | String | `reaction.key` | Direct | Reaction relation type (could be non-emoji) |
| `count` | Int | `reaction.senders.count` | Count calculation | Individual sender timestamps |
| `senderIDs` | [String] | `reaction.senders.map(\.senderId)` | Extraction | Sender annotation details |
| `includesMe` | Bool | `senders.contains { $0.senderId == myUserID }` | Boolean check | My reaction timestamp |

**SDK Data Available but NOT Mapped:**
- `Reaction`:
  - `key` — could be non-emoji text (annotation)
  - `senders`:
    - `SenderId` type (user ID only, no profile)
    - Timestamp data (when reacted) — NOT EXPOSED
- Related event relations:
  - `relates_to.inReplyTo` — reply events
  - `relates_to.replace` — edit events
  - Relations as separate `TimelineItem`s — not exposed

---

### VerificationState

**Enum Variants (8 total):**

| Variant | SDK Source | Transformations | Data Lost |
|---|---|---|---|
| `idle` | Initial state | Direct | — |
| `requested` | `VerificationDelegate.onRequest()` | Direct | Incoming request details |
| `waitingForAcceptance` | Manual `.yield()` in adapter | Manual state | — |
| `showingEmoji([VerificationEmoji])` | `didReceiveVerificationData(.emojis/decimals)` | Emoji objects mapped | QR code verification |
| `confirmed` | `didFinish()` | Direct | — |
| `failed(String)` | `didFail()` + `RecoveryError` mapping | Generic string | Error details (type lost) |
| `timedOut` | (Not emitted by SDK) | Hardcoded in enum | SDK doesn't timeout; app must detect |
| `cancelled` | `didCancel()` | Direct | Cancellation reason |

**VerificationEmoji struct:**
```
SessionVerificationEmoji (SDK)
  → symbol() → VerificationEmoji.symbol
  → description() → VerificationEmoji.description
```

**Key SDK Data Not Mapped:**
- `SessionVerificationRequestDetails`:
  - `senderProfile` — who sent request
  - `flowId` — verification flow ID
  - `methods` — supported verification methods
  - `otherDeviceId` — which device is requesting
- `SessionVerificationData.Qr` — QR verification not exposed
- Decimal verification — shown as text, not structured
- Verification timeout — not detected/emitted
- Verification method selection — always SAS

---

## 3. CROSS-CUTTING PATTERNS

### Stream-Based Abstraction

All continuous operations use `AsyncStream`:
- `AuthServiceProtocol.authStateStream()` → `AsyncStream<AuthState>`
- `SyncServiceProtocol.roomListStream()` → `AsyncStream<[NebRoom]>`
- `RoomServiceProtocol.timelineStream()` → `AsyncStream<[NebMessage]>`
- `CryptoServiceProtocol.verificationStateStream()` → `AsyncStream<VerificationState>`
- `CryptoServiceProtocol.deviceVerificationStatusStream()` → `AsyncStream<DeviceVerificationStatus>`
- `TypingServiceProtocol.typingUsersStream()` → `AsyncStream<[NebUser]>`

**SDK Pattern:** Listener objects (objects implementing SDK listener protocols)
**NebCore Pattern:** `AsyncStream` continuations (no SDK listener exposure)

This adds one layer of indirection but maintains a clean, Swift-native API.

### Listener Retention Pattern

All SDK listeners must be retained as properties (critical issue noted in CLAUDE.md):

- `MatrixSyncAdapter`:
  - `entriesListener: NebRoomListEntriesListener?`
  - `entriesHandle: TaskHandle?`
  - `entriesController: RoomListDynamicEntriesController?`

- `MatrixRoomAdapter`:
  - `activeTimelines: [String: TimelineHandle]` (contains `listener`, `listenerHandle`)

- `MatrixCryptoAdapter`:
  - `delegate: VerificationDelegate?`
  - `deviceVerificationListener: DeviceVerificationStateListener?`
  - `verificationStateHandle: TaskHandle?`

- `MatrixTypingAdapter`:
  - Listener passed to `room.subscribeToTypingNotifications()`
  - Handle captured in `continuation.onTermination` closure

**If listeners are not retained:** SDK deallocates them immediately → crashes

### Error Handling

Different strategies per protocol:

**AuthServiceProtocol:** Rethrows SDK errors directly
```swift
do {
    try await client.login(...)
} catch {
    logger.error("Login failed: \(error.localizedDescription)")
    throw error
}
```

**CryptoServiceProtocol:** Maps `RecoveryError` to `NebError`
```swift
catch let error as RecoveryError {
    switch error {
    case .SecretStorage:
        throw NebError.recoveryFailed("Could not find secret storage data...")
    case .Import:
        throw NebError.recoveryFailed("Invalid recovery key...")
    }
}
```

**RoomServiceProtocol:** Returns `NebError.notLoggedIn` or `NebError.roomNotFound()`

**SyncServiceProtocol:** Rethrows directly; no custom errors

**NotificationServiceProtocol:** Logs errors, doesn't throw

### Async State Access

**Pattern 1: Property getter**
```swift
public var authState: AuthState { get async { _authState } }
```

**Pattern 2: Stream creation**
```swift
public func authStateStream() -> AsyncStream<AuthState> {
    AsyncStream { continuation in
        self.continuation = continuation
        continuation.yield(self._authState)
    }
}
```

Issue: Eager state access requires `get async`, which is uncommon in Swift.

---

## 4. SDK FEATURES NOT EXPOSED AT ALL

### Room Management
- Room creation parameters (visibility, join rules, power levels)
- Room state editing (topic, avatar, name)
- Room member management (kick, ban, invite)
- Room history visibility settings
- Room retention policies
- Room tags/favorites

### Message Operations
- Message replies/threading
- Message mentions (user/room)
- Message search
- Message previews (rich content)
- Attachment handling (upload, download, preview)
- Custom message types (emotes, notices, etc.)
- Message relation details (full edit history, reply chains)

### User Operations
- User profile updates
- User presence (online/offline/idle)
- User account settings
- User account data (preferences stored on server)
- User avatar caching policy control

### Encryption & Security
- QR code verification
- Manual key verification
- Cross-signing key recovery details
- Backup recovery codes
- Device list management
- Secret sharing (password setup)

### Sync & Events
- Event types beyond messages (state changes, calls, etc.)
- Room initial sync state
- Presence sync
- Account data sync
- Sync filters
- Sliding sync pagination controls

### Matrix Federation
- User ID validation
- Server capability discovery
- Room federation status
- Event origin server

---

## 5. DELIBERATE OMISSIONS (Design Choices)

These are API surface limitations that appear intentional:

| Omission | Reason | Impact |
|---|---|---|
| No raw SDK types exposed | Loose coupling to SDK | Views never depend on SDK changes |
| No event types | Simplified model | Non-message events silently dropped |
| No edit history | Stateless timeline | Edit chains not preserved |
| No threading support | Simplified room model | Replies shown as messages in timeline |
| No media handling | Out of scope | No image preview, file downloads |
| No presence | Simplified | No "online/typing/away" distinction beyond typing |
| No user profiles (edit) | Read-only user model | Users can't change display name from app |
| No custom events | Scope limit | Extensions/plugins not possible |
| `memberCount` always 0 | Performance (not called) | Room member count never shown |

---

## 6. SUMMARY TABLE: Protocol → Adapter → SDK Mapping

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        NebCore Abstraction Layer                        │
├──────────────┬─────────────────────────┬──────────────┬─────────────────┤
│ Protocol     │ # Methods               │ # Models     │ SDK Adapters    │
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Auth         │ 5 (login, restore,      │ —            │ MatrixAuthAdapter
│              │   logout, state, stream)│              │ (1 adapter)
│              │                         │              │ SDK: Client,
│              │                         │              │ ClientBuilder,
│              │                         │              │ Session
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Sync         │ 3 (startSync, stopSync, │ NebRoom (9   │ MatrixSyncAdapter
│              │   roomListStream)       │ fields)      │ (1 adapter)
│              │                         │              │ SDK: SyncService,
│              │                         │              │ RoomListService,
│              │                         │              │ RoomListEntries,
│              │                         │              │ Room.roomInfo(),
│              │                         │              │ Room.membersNoSync()
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Room         │ 7 (timeline, send msg,  │ NebMessage   │ MatrixRoomAdapter
│              │   read receipt, DM,     │ (15 fields)  │ (1 adapter)
│              │   paginate, reaction,   │ ReadReceipt  │ SDK: Room,
│              │   edit)                 │ (3 fields)   │ Timeline,
│              │                         │ NebReaction  │ TimelineItem,
│              │                         │ (4 fields)   │ MessageEventContent
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Crypto       │ 11 (device/user verif., │ VerificationState
│              │   accept, confirm,      │ (8 variants) │ MatrixCryptoAdapter
│              │   decline, cancel,      │ VerificationEmoji
│              │   state streams, backup)│ (2 fields)   │ SDK: Session
│              │                         │ DeviceVerifStatus
│              │                         │ (enum: 3 vals)
│              │                         │              │ VerificationController,
│              │                         │              │ Encryption,
│              │                         │              │ UserIdentity,
│              │                         │              │ SessionVerificationData
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Typing       │ 2 (send notice, stream) │ NebUser (4   │ MatrixTypingAdapter
│              │                         │ fields)      │ (1 adapter)
│              │                         │              │ SDK: Room.typing,
│              │                         │              │ RoomMember
├──────────────┼─────────────────────────┼──────────────┼─────────────────┤
│ Notification │ 3 (permission, post,    │ —            │ MatrixNotification
│              │   badge)                │              │ Adapter
│              │                         │              │ SDK: NONE
│              │                         │              │ (native UNCenter)
└──────────────┴─────────────────────────┴──────────────┴─────────────────┘
```

---

## 7. DATA LOSS BY CATEGORY

### Critical SDK Features Completely Hidden
1. **SDK Client object** — never exposed
2. **Event types** — only messages (filters out 95% of events)
3. **User profiles** — read-only, minimal
4. **Device management** — not accessible from app
5. **Room state** — limited (isDirect, unread, avatar only)
6. **Message relations** — edits/replies not exposed as chains
7. **Custom events** — not supported

### Data Lossy Conversions
1. **Unread count** — `max(numUnreadMessages, numUnreadNotifications)` — distinction lost
2. **Send status** — 4 SDK states → 3 NebCore states (details lost)
3. **Formatted body** — only HTML; Markdown format identifier lost
4. **Read receipts** — no timestamp data
5. **Reactions** — sender timestamps not exposed
6. **Member avatars** — used but not stored as primary DM avatar source
7. **Recovery errors** — 5 SDK types → 1 generic "failed" state

### Data Never Fetched
1. **Room member count** — `room.memberCount()` exists but never called
2. **Room favorite status** — `room.isFavourite()` not checked
3. **Room topic** — `room.roomInfo().topic` not accessed
4. **User verification details** — `isVerified` always false in typing
5. **Edit history** — not stored/accessed
6. **Event full JSON** — never accessed for extensions

---

## Conclusion

**NebCore provides a thin, intentional abstraction** that:

✅ **Achieves:** Clean separation of concerns, SDK opacity, simple async streams, type safety
❌ **Sacrifices:** Feature completeness, extensibility, detailed state visibility

The adapter-to-protocol mapping shows **clear lines drawn around the feature set** — messaging, rooms, auth, typing, crypto, notifications. Features outside these domains (room state editing, presence, accounts, federation) are not exposed.

The most significant data loss occurs in:
1. **Event filtering** (only messages, not state events)
2. **Relation handling** (no threading, replies, edit chains)
3. **User/room metadata** (limited to display essentials)
4. **Verification details** (QR not supported, error details flattened)

This is a **deliberate design** prioritizing app simplicity over SDK comprehensiveness.
