# MatrixRustSDK Technical Reference

**Version:** 26.5.13  
**Language:** Swift (FFI bindings to Rust SDK)  
**Generated from:** matrix-rust-components-swift

## Core Objects & Methods

### Client
**Main entry point for all SDK operations**

```swift
// Authentication
func login(username: String, password: String, 
           initialDeviceName: String?, deviceId: String?) async throws
func restoreSession(session: Session) async throws
func logout() async throws

// Session
func userId() throws -> String
func session() throws -> Session

// Room access
func getRoom(roomId: String) throws -> Room?
func getDmRoom(userId: String) throws -> Room?
func createRoom(request: CreateRoomParameters) async throws -> String

// Sync
func syncService() async throws -> SyncServiceBuilder

// Encryption
func encryption() -> Encryption
func getSessionVerificationController() async throws -> SessionVerificationController

// Media
func getMediaThumbnail(mediaSource: MediaSource, width: UInt32, 
                      height: UInt32, resizeMethod: ResizeMethod, 
                      useWarmCache: Bool = true) async throws -> Data

// Profile
func profile(userId: String) async throws -> UserProfile
func setDisplayName(name: String) async throws
func uploadAvatar(mxcUrl: String) async throws

// Account
func account() async throws -> Account
func sendPresence(presence: Presence, statusMsg: String?) async throws

// Search
func search(query: String) -> GlobalSearchIterator
```

### ClientBuilder
**Configures client before construction**

```swift
// Chainable configuration
func serverNameOrHomeserverUrl(serverNameOrUrl: String) -> ClientBuilder
func homeserverUrl(url: String) -> ClientBuilder
func sessionPaths(dataPath: String, cachePath: String) -> ClientBuilder
func slidingSyncVersionBuilder(versionBuilder: SlidingSyncVersionBuilder) -> ClientBuilder
func autoEnableCrossSigning(autoEnableCrossSigning: Bool) -> ClientBuilder
func autoEnableBackups(autoEnableBackups: Bool) -> ClientBuilder
func eventCacheStore(store: UInt64) -> ClientBuilder
func cryptoStore(store: UInt64) -> ClientBuilder

// Build
func build() async throws -> Client
```

### Session
**Persistent session storage**

```swift
let accessToken: String
let refreshToken: String?
let userId: String
let deviceId: String
let homeserverUrl: String
let oidcData: String?
let slidingSyncVersion: SlidingSyncVersion
```

### SyncService
**Background sync loop**

```swift
// Control
func start() async
func stop() async

// Room list access
func roomListService() -> RoomListService
```

### RoomListService
**Manages user's rooms list**

```swift
// Get rooms
func allRooms() -> RoomList
func invitedRooms() -> RoomList
func joinedRooms() -> RoomList

// Subscriptions
func subscribeToRooms(roomIds: [String]) async throws
func unsubscribeFromRooms(roomIds: [String]) async throws
```

### RoomList
**Collection of rooms with streaming updates**

```swift
// Entries
func entriesWithDynamicAdapters(pageSize: UInt32, 
                               listener: RoomListEntriesListener) 
                               -> RoomListEntriesWithDynamicAdaptersResult
```

### RoomListDynamicEntriesController
**Filter and control room list**

```swift
func setFilter(kind: RoomListFilterKind) -> Bool

// Filter kinds:
// - .all(filters: [])           // All rooms, optionally filtered
// - .invited                     // Invited rooms only
// - .joined                      // Joined rooms only
// - .empty                       // Empty rooms only
```

### Room
**Individual room context**

```swift
// Identity
func id() -> String
func displayName() -> String?

// Info
func roomInfo() throws -> RoomInfo

// Members
func membersNoSync() -> RoomMemberPaginator
func membersCount() -> UInt64
func activeMembersCount() -> UInt64
func cachedMembers() -> [Member]?
func updateMembers() async throws

// Member operations
func invite(userId: String) async throws
func kick(userId: String, reason: String?) async throws
func ban(userId: String, reason: String?) async throws
func unban(userId: String) async throws

// State - Query
func canonicalAlias() throws -> String?
func alternativeAliases() throws -> [String]
func topic() throws -> String?
func guestAccess() throws -> GuestAccess
func joinRule() throws -> JoinRule
func historyVisibility() throws -> HistoryVisibility
func encryption() throws -> String?  // "m.megolm.v1.aes-sha2"

// State - Modify
func setName(name: String) async throws
func setTopic(topic: String) async throws
func setAvatar(mxcUrl: String) async throws
func setGuestAccess(access: GuestAccess) async throws
func setJoinRule(rule: JoinRule) async throws
func setHistoryVisibility(visibility: HistoryVisibility) async throws
func setPowerLevels(powerLevels: PowerLevels) async throws

// Messages
func timeline() async throws -> Timeline
func markAsRead(receiptType: ReceiptType) async throws

// Typing
func typingNotice(isTyping: Bool) async throws
func subscribeToTypingNotifications(listener: TypingNotificationsListener) -> TaskHandle

// Attachments
func sendAttachment(localPath: String, mimeType: String) async throws -> SendHandle

// Notifications
func notificationMode() -> RoomNotificationMode?
func setNotificationMode(mode: RoomNotificationMode) async throws

// Tags
func addTag(tag: String, order: Double?) async throws
func removeTag(tag: String) async throws

// Search
func search(query: String) -> RoomSearchIterator

// Live location
func startLiveLocationShare(label: String?, timeout: UInt64?) 
                          -> LiveLocationsObserver?
```

### Timeline
**Message stream for a room**

```swift
// Send
func send(msg: MessageEventContent) async throws -> SendHandle

// Edit
func edit(eventOrTransactionId: EventOrTransactionId, 
         newContent: RoomMessageEventContentWithoutRelation) async throws

// Reactions
func toggleReaction(itemId: EventOrTransactionId, key: String) async throws
func addReaction(itemId: EventOrTransactionId, emoji: String) async throws
func removeReaction(itemId: EventOrTransactionId, emoji: String) async throws

// Redaction
func redact(itemId: EventOrTransactionId, reason: String?) async throws

// Replies
func sendReply(message: MessageEventContent, replyTo: String) async throws
func sendInThread(message: MessageEventContent, threadId: String) async throws
func getInThreadTimeline(threadId: String) async throws -> Timeline

// Pagination
func paginateBackwards(numEvents: UInt16) async throws -> UInt16
func paginateForwards(numEvents: UInt16) async throws -> UInt16
func paginate(direction: PaginationDirection, numEvents: UInt16) async throws -> UInt16

// State
var focusedEventId: String? { get }
var canRewind: Bool { get }
var canForwardPaginate: Bool { get }

// Listeners
func addListener(listener: TimelineListener) async -> TaskHandle

// Polls
func sendPoll(question: String, answers: [String]) async throws
func answerPoll(pollEventId: String, answer: String) async throws

// Lazy loading
var lazyProvider: LazyTimelineItemProvider? { get }
```

### TimelineItem
**Single item in timeline (event or virtual)**

```swift
func asEvent() -> Event?  // Returns nil for virtual items
func asVirtual() -> VirtualTimelineItem?  // Returns nil for events
```

### Event
**Matrix event in timeline**

```swift
// Identity
var eventOrTransactionId: EventOrTransactionId { get }  // .eventId or .transactionId
var sender: String { get }
var timestamp: Int64 { get }  // Milliseconds since epoch

// Content
var content: TimelineItemContent { get }  // .msgLike(...), .state(...), etc.

// State
var isOwn: Bool { get }
var isEditable: Bool { get }
var localSendState: LocalSendState? { get }  // notSentYet, sendingFailed, sent

// Metadata
var senderProfile: SenderProfile { get }  // .ready(displayName, _, avatarUrl)
var readReceipts: [String: ReceiptType] { get }  // Map of userID -> receipt type
```

### MessageEventContent
**Text message content**

```swift
let body: String
let isEdited: Bool
let msgType: MessageType  // .text(FormattedMessageText), .image, .video, etc.

// msgType.text properties:
// - FormattedMessageText.body: String (plain text)
// - FormattedMessageText.formatted: FormattedBody? (HTML)
//   - format: "org.matrix.custom.html"
//   - body: String (HTML content)
```

### Encryption
**Cryptography and verification**

```swift
// State
func verificationState() -> VerificationState  // verified, unverified, unknown
func recoveryState() -> RecoveryState

// Listeners
func verificationStateListener(listener: VerificationStateListener) -> TaskHandle
func backupStateListener(listener: BackupStateListener) -> TaskHandle

// Backup
func backupExistsOnServer() async throws -> Bool
func backupRecoveryKey() async throws -> String
func enableBackupV1() async throws
func disableBackupV1() async throws

// Recovery
func recoverAndFixBackup(recoveryKey: String) async throws
func requestMissingRoomKeys() async throws
func waitForE2eeInitializationTasks() async

// Identity verification
func userIdentity(userId: String, fallbackToServer: Bool) async throws -> UserIdentity?

// Device management
func devices() async throws -> [Device]
```

### SessionVerificationController
**Device/user verification flow**

```swift
// Request
func requestDeviceVerification() async throws
func requestUserVerification(userId: String) async throws

// Receive
func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws
func acceptVerificationRequest() async throws

// SAS (emoji matching)
func startSasVerification() async throws
func approveVerification() async throws
func declineVerification() async throws

// Lifecycle
func cancelVerification() async throws

// Callback
func setDelegate(delegate: SessionVerificationControllerDelegate)
```

### UserIdentity
**User's verification status**

```swift
func isVerified() -> Bool  // Any verification
func isCrossSigned() -> Bool  // Full cross-signing chain
```

---

## Enums & Constants

### EventOrTransactionId
```swift
case eventId(eventId: String)
case transactionId(id: String)
```

### TimelineItemContent
```swift
case msgLike(MessageLikeEventContent)
case state(StateEventContent)
case virtual(VirtualTimelineItem)
```

### MessageLikeEventContent
```swift
var kind: MessageEventContentKind { get }  // .message, .unableToDecrypt, etc.
var reactions: [String: [ReactionSenderInfo]] { get }  // emoji -> list of senders
```

### LocalSendState
```swift
case notSentYet(error: String?)
case sendingFailed(error: String?, isFatalError: Bool)
case sent(eventId: String)
```

### SenderProfile
```swift
case ready(displayName: String?, avatar: String?, avatarUrl: String?)
case unavailable
case pending
```

### ReceiptType
```swift
case read
case readPrivate
case typing
```

### RoomNotificationMode
```swift
case mute
case mentionOnly
case allMessages
```

### JoinRule
```swift
case public
case knock
case invite
case private
```

### HistoryVisibility
```swift
case worldReadable
case shared
case invited
case joined
```

### Presence
```swift
case online
case offline
case unavailable
```

### VerificationState
```swift
case verified
case unverified
case unknown
```

### ResizeMethod
```swift
case crop
case scale
```

### PaginationDirection
```swift
case backwards
case forwards
```

### RoomListFilterKind
```swift
case all(filters: [RoomListFilter])
case invited
case joined
case empty
```

### RoomListEntriesUpdate
```swift
case append(values: [Room])
case clear
case pushFront(value: Room)
case pushBack(value: Room)
case popFront
case popBack
case insert(index: UInt32, value: Room)
case set(index: UInt32, value: Room)
case remove(index: UInt32)
case truncate(length: UInt32)
case reset(values: [Room])
```

### TimelineDiff
```swift
case append(values: [TimelineItem])
case clear
case pushFront(value: TimelineItem)
case pushBack(value: TimelineItem)
case popFront
case popBack
case insert(index: UInt32, value: TimelineItem)
case set(index: UInt32, value: TimelineItem)
case remove(index: UInt32)
case truncate(length: UInt32)
case reset(values: [TimelineItem])
```

---

## Listeners & Callbacks

### RoomListEntriesListener
```swift
protocol RoomListEntriesListener {
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate])
}
```

### TimelineListener
```swift
protocol TimelineListener {
    func onUpdate(diff: [TimelineDiff])
}
```

### TypingNotificationsListener
```swift
protocol TypingNotificationsListener {
    func call(typingUserIds: [String])
}
```

### VerificationStateListener
```swift
protocol VerificationStateListener {
    func onUpdate(status: VerificationState)
}
```

### SessionVerificationControllerDelegate
```swift
protocol SessionVerificationControllerDelegate {
    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails)
    func didAcceptVerificationRequest()
    func didStartSasVerification()
    func didReceiveVerificationData(data: SessionVerificationData)
    func didFail()
    func didCancel()
    func didFinish()
}
```

### AccountDataListener
```swift
protocol AccountDataListener {
    func onAccountData(type: String, content: [String: Any])
}
```

### PresenceListener
```swift
protocol PresenceListener {
    func onPresenceUpdate(userId: String, presence: Presence)
}
```

### BackupStateListener
```swift
protocol BackupStateListener {
    func onUpdate(state: BackupState)
}
```

### BeaconInfoListener
```swift
protocol BeaconInfoListener {
    func onUpdate(beacon: BeaconInfo)
}
```

---

## Paginated Iterators

### RoomMemberPaginator
```swift
func nextChunk(chunkSize: UInt32) async throws -> [Member]?

// Member properties:
// - userId: String
// - displayName: String?
// - avatarUrl: String?
// - membership: Membership (.join, .leave, .invite, .ban, .knock)
```

### GlobalSearchIterator
```swift
func nextChunk(chunkSize: UInt32) async throws -> [SearchResult]?
```

### RoomSearchIterator
```swift
func nextChunk(chunkSize: UInt32) async throws -> [TimelineItem]?
```

---

## Helper Functions

```swift
// Message creation from markdown
func messageEventContentFromMarkdown(md: String) -> MessageEventContent

// Media
func MediaSource.fromJson(json: String) throws -> MediaSource
func MediaSource.fromUrl(url: String) throws -> MediaSource

// QR Code
func QrCodeData.fromBytes(bytes: Data) throws -> QrCodeData
```

---

## Summary Table

| Domain | Core Types | Methods (approx) |
|--------|-----------|-----------------|
| Authentication | Client, ClientBuilder, Session | 8 |
| Sync & Rooms | SyncService, RoomListService, RoomList | 7 |
| Room State | Room | 40 |
| Timeline | Timeline, TimelineItem, Event | 20 |
| Messages | MessageEventContent | 15 |
| Encryption | Encryption, SessionVerificationController | 25 |
| Media | MediaSource, MediaFileHandle | 10 |
| Search | GlobalSearchIterator, RoomSearchIterator | 8 |
| Account | Client (profile, presence) | 12 |
| Listeners | Various interfaces | 10 |
| **TOTAL** | | **~155** |

> Note: This is an estimate. The SDK has ~500+ public methods when including all overloads and variants.

