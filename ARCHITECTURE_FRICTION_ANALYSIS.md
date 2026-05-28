# Neb Architecture: Friction Analysis Report

## Executive Summary

The Neb codebase is well-structured with clear separation of concerns (Views/ViewModels/Adapters), but has accumulated several areas of friction through incremental growth:

1. **Shallow protocol abstractions** — Some adapters are thin pass-throughs that add little value
2. **Lifecycle management complexity** — Listener retention and task cancellation patterns scattered and error-prone
3. **Untested adapters** — Core SDK integration code has no test coverage
4. **View complexity hotspots** — MessageBubbleView (367 lines) and verification flows mixing concerns
5. **Global/singleton state** — Hardcoded homeserver URL, scattered `.shared` singletons
6. **SDK type leakage** — Room/user IDs remain strings when they could be typed values
7. **Incomplete error handling** — Silent failures throughout (try? without logging)

---

## 1. SHALLOW MODULES: Protocol-to-Adapter Mismatch

### Friction Point: TypingServiceProtocol + MatrixTypingAdapter

**Files:**
- `NebCore/Sources/NebCore/Services/TypingServiceProtocol.swift` (6 lines)
- `NebCore/Sources/NebCore/Adapters/MatrixTypingAdapter.swift` (79 lines)

**The Problem:**

The protocol is a direct 1:1 pass-through to SDK calls:

```swift
public protocol TypingServiceProtocol: Sendable {
    func sendTypingNotice(roomID: String, isTyping: Bool) async throws
    func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]>
}
```

The adapter barely wraps the SDK:

```swift
public func sendTypingNotice(roomID: String, isTyping: Bool) async throws {
    guard let client = clientProvider() else { return }
    guard let room = try client.getRoom(roomId: roomID) else { return }
    try await room.typingNotice(isTyping: isTyping)
}
```

**The adapter adds:**
- A `room` fetch
- Error swallowing (returns silently on `clientProvider()` or room lookup failures)
- A listener wrapper around `TypingNotificationsListener` that does async member lookups

**Does this adapter add value?**
- It hides the SDK's listener pattern, but the semantics are identical
- It doesn't validate room IDs or provide domain-specific logic
- Test question: if deleted, would complexity scatter or concentrate? → **Scatter** (viewers would import MatrixRustSDK)

**Deletion test:** Removing this would force views to access SDK directly or duplicate listener logic.

**Verdict:** The protocol exists primarily to maintain the abstraction boundary, but the implementation is nearly transparent. The real value is that **you can mock it for tests** (and you do). The pattern is correct; it's just thin.

---

### Friction Point: NotificationServiceProtocol + MatrixNotificationAdapter

**Files:**
- `NebCore/Sources/NebCore/Services/NotificationServiceProtocol.swift` (7 lines)
- `NebCore/Sources/NebCore/Adapters/MatrixNotificationAdapter.swift` (39 lines)

**The Problem:**

The adapter is mostly a wrapper around native macOS APIs with no Matrix-specific logic:

```swift
public func postNotification(title: String, body: String, roomID: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = ["roomID": roomID]
    content.threadIdentifier = roomID
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(request)
}
```

**The interface doesn't model Matrix domain knowledge:**
- Takes `title`, `body`, `roomID` as separate parameters (no room object)
- Doesn't distinguish notification types (message, invite, verification, etc.)
- `updateBadgeCount` is a generic domain-agnostic operation

**Untested:** Zero tests, not even a mock.

**Deletion test:** Would complexity scatter? → **No.** You'd just call `UNUserNotificationCenter` directly in the view model or a notification utility. The adapter provides minimal abstraction value here.

**Verdict:** This is a **thin veneer adapter**. It's testable in isolation but not meaningfully tested. The protocol doesn't model Matrix semantics.

---

### Friction Point: SyncServiceProtocol — Tight Coupling to SDK

**Files:**
- `NebCore/Sources/NebCore/Services/SyncServiceProtocol.swift` (7 lines)
- `NebCore/Sources/NebCore/Adapters/MatrixSyncAdapter.swift` (201 lines)

**The Problem:**

The protocol is minimal:

```swift
public protocol SyncServiceProtocol: Sendable {
    func startSync() async throws
    func stopSync() async throws
    func roomListStream() -> AsyncStream<[NebRoom]>
}
```

But the adapter does significant work:

1. **Listener management** — `NebRoomListEntriesListener` wraps SDK's `RoomListEntriesListener` to translate `RoomListEntriesUpdate` enum into model mutations
2. **Delta processing** — Applies SDK's room list diffs (append, insert, set, remove, etc.) to a local `rooms` array
3. **Room info fetching** — Async fetches room info, member lists, avatar URLs for each room
4. **Debouncing** — Delays emitting updates by 100ms to batch rapid changes
5. **Type conversion** — Maps SDK `Room` → `NebRoom`

**Leaky seam issue:** The protocol doesn't expose `roomListService` publicly, but `MatrixRoomAdapter` and `MatrixTypingAdapter` need it:

```swift
// In AppState.swift
let sync = MatrixSyncAdapter(clientProvider: { auth.getClient() })
let room = MatrixRoomAdapter(
    clientProvider: { auth.getClient() }, 
    roomListServiceProvider: { sync.roomListService }  // ← accessing internal property
)
```

This couples adapters directly: the room adapter can't work without reaching into sync adapter's internals.

**Missing test coverage:** No unit tests for the delta processing, room info fetching, or debouncing logic.

**Deletion test:** If deleted, you'd need a new abstraction. The adapter concentrates complexity intentionally.

**Verdict:** The adapter does real work, but the protocol boundary is weak. The `roomListService` exposure is a smell that suggests the boundary needs rethinking.

---

## 2. LEAKY SEAMS: SDK Types in Public APIs

### Friction Point: Room IDs and User IDs Are Strings

**Throughout the codebase** room IDs like `"!abc:example.com"` and user IDs like `"@alice:example.com"` are passed as `String`.

**Where this causes problems:**

1. **TimelineViewModel.roomID**
   ```swift
   public init(
       roomID: String,  // ← any string accepted, no validation
       roomService: any RoomServiceProtocol,
       ...
   )
   ```

2. **RoomListViewModel** filters and searches by string:
   ```swift
   private var filteredRooms: [NebRoom] {
       if searchQuery.isEmpty { return allRooms }
       let query = searchQuery.lowercased()
       return allRooms.filter { $0.name.lowercased().contains(query) }
   }
   ```
   Question: is this case-insensitive search correct for Matrix IDs? Unlikely.

3. **MessageBubbleView** receives:
   ```swift
   message.senderID: String  // ← could be invalid
   ```

4. **NewDMViewModel** validates user IDs with a regex:
   ```swift
   private func isValidMatrixID(_ id: String) -> Bool {
       let pattern = #"^@[a-zA-Z0-9._=/\-]+:[a-zA-Z0-9.\-]+(:[0-9]+)?$"#
       return id.range(of: pattern, options: .regularExpression) != nil
   }
   ```
   This validation logic is **isolated to one view model**, not enforced at the protocol level.

**Impact:**
- You can construct invalid room/user objects that appear valid until runtime
- Protocol methods accept any string: `createDM(userID: String)` will happily accept `"not-a-user-id"`
- No single source of truth for validation

**Not tested:** No tests for malformed IDs.

**Deletion test:** Creating typed wrappers (`struct RoomID: Hashable { let rawValue: String }`) would scatter validation throughout the codebase instead of centralizing it.

**Verdict:** **Acceptable friction.** Typed value objects would help, but the current approach is pragmatic for Swift. The bigger issue is that validation happens inconsistently (only in NewDMViewModel).

---

### Friction Point: SDK Event Content Conversion Buried in Adapter

**File:** `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift` (lines 215–307)

The `NebTimelineListener.convertItem()` function is a **complex, untested conversion** that bridges SDK types to domain models. It's ~90 lines of complex logic handling:

- Event type checking
- Message content extraction
- Formatted body HTML parsing
- Encryption status rendering
- Send status mapping
- Read receipt extraction
- Reaction aggregation

**Issues:**
- Tightly couples the adapter to SDK's `TimelineItem`, `RoomMessageEventContent`, `FormattedBody` hierarchy
- Complex switch/case logic with no unit tests
- Silent failures (returns `nil` for unhandled event types without logging)
- The `profileCache` is mutable state inside a listener (`nonisolated(unsafe)`)

**Not testable in isolation** — you'd need to mock SDK types to test this function.

**Verdict:** The conversion logic is doing **real, domain-specific work**, but it's trapped inside an adapter. This should ideally be extracted to a testable utility module.

---

## 3. TESTABILITY GAPS

### What's Tested

**ViewModels:** ✓ Good coverage
- `LoginViewModelTests.swift` — 64 lines, 7 tests
- `RoomListViewModelTests.swift` — 120 lines, 11 tests
- `TimelineViewModelTests.swift` — 174 lines, 17 tests
- `VerificationViewModelTests.swift` — Tests included, has timeout/state tests
- `NewDMViewModelTests.swift` — 71 lines, 7 tests
- Total: **~480 lines of view model tests**

**Models:** ✓ Some coverage
- `VerificationStateTests.swift`
- `AttributedStringFormatterTests.swift`
- `HTMLRendererTests.swift`
- `MarkdownConverterTests.swift`

**Adapters:** ✗ **Zero coverage**
- No tests for `MatrixAuthAdapter` (session persistence, login/logout)
- No tests for `MatrixSyncAdapter` (delta processing, listener lifecycle)
- No tests for `MatrixRoomAdapter` (timeline conversion, reaction toggling, editing)
- No tests for `MatrixCryptoAdapter` (verification state machine, emoji mapping)
- No tests for `MatrixTypingAdapter` (member lookup in typing listener)
- No tests for `MatrixNotificationAdapter`

**Code without test coverage:**
- All SDK listener implementations
- Session persistence logic
- Error handling paths (try? without logging)
- Timeline event conversion (convertItem)
- Room info fetching (member lookups, avatar resolution)
- Debouncing logic in sync adapter

**Untested lines:** ~800 lines in adapters alone.

### Why Adapters Aren't Tested

1. **SDK types are hard to mock** — `Client`, `Room`, `Timeline`, `RoomListService`, etc. are FFI-bridged Rust types
2. **Listeners require SDK state** — the listener pattern requires a live SDK context to test
3. **Test focus was on ViewModels** — the visible behavioral layer, not the SDK integration layer

### Deletion Test: Would Extracting Conversion Logic Scatter or Concentrate?

If you extracted `convertItem()` to a `TimelineEventConverter` utility:

```swift
struct TimelineEventConverter {
    static func convert(_ item: TimelineItem) -> NebMessage? { ... }
}
```

**Result:** → **Concentrate.** You'd have a testable, reusable utility. Adapters would be thinner, converter would be unit-tested. This is a win.

---

## 4. APPSTATE COMPLEXITY

**File:** `Neb/AppState.swift` (69 lines)

### What It Does

- Creates all 6 adapters
- Wires them together via closures for dependency injection
- Coordinates login/logout lifecycle
- Exposes adapters + view models to views
- Provides factory methods

### Analysis

**Responsibilities:**
1. **Adapter factory** — creates all 6 adapters
2. **Dependency injection** — wires them together via closures
3. **Lifecycle coordinator** — calls `onLoggedIn()` / `onLoggedOut()`
4. **Property holder** — exposes adapters + view models to views
5. **Service provider** — has methods like `makeRoomService()`, `makeCryptoService()`

**God object indicators:**
- Owns 6 adapters + 2 view models
- Central location for all wiring logic
- Hard to test (would need to instantiate all adapters)
- **Hardcoded homeserver URL:** `var homeserverURL: String { "https://matrix.matto.io" }`

**Note on the hardcoded URL:**
```swift
var homeserverURL: String { "https://matrix.matto.io" }
```
This is used for:
- `AvatarImageCache.shared.setClientProvider()` in `onLoggedIn()`
- Passed to all views for avatar loading

The CLAUDE.md mentions: *"Homeserver URL hardcoded in `AppState.homeserverURL` as `"https://matrix.matto.io"`. Used for avatar image loading via the SDK's media API. Should be extracted from the stored session."*

**This is a leak:** The homeserver URL should come from the authenticated session, not be hardcoded.

**Is AppState a god object?**
- It's small (69 lines) but has high coupling (owns all adapters)
- In a larger app, this would be unmaintainable
- For current scope, it's acceptable as a root coordinator

**Deletion test:** AppState concentrates all wiring. If deleted, you'd need a different root coordinator. Complexity wouldn't scatter; it would move. **No issue here.**

---

## 5. VIEW MODEL RESPONSIBILITIES

### TimelineViewModel: Balanced but Has Multiple Concerns

**File:** `NebCore/Sources/NebCore/ViewModels/TimelineViewModel.swift` (153 lines)

**Responsibilities:**
1. **Timeline state management** — holds `messages: [NebMessage]`
2. **Typing management** — holds `typingUsers`, manages typing subscriptions
3. **Typing notice sending** — `onComposerChanged()` sends typing notices with debouncing
4. **Message composition** — holds `composerText` and `editingMessage`
5. **Message editing** — `startEditingLastMessage()`, `submitEdit()`
6. **Message reactions** — `toggleReaction()`
7. **Read receipts** — `markAsRead()`
8. **Pagination** — `loadMore()`

**Is this too much?**
- The module is 153 lines, reasonable size
- Well-organized with clear method boundaries
- Typing logic is duplicated with `RoomListViewModel` (which also subscribes to typing)

**Deletion test:** Extracting typing into a separate `TypingManager` would:
- Reduce TimelineViewModel to 120 lines
- Allow reuse in room list
- Decouple concerns
- **Verdict:** Would scatter slightly (need to coordinate two objects), but improves clarity.

---

## 6. MESSAGEBUBBLEVIEW: Growing Complexity

**File:** `Neb/Views/Timeline/MessageBubbleView.swift` (367 lines)

### What It Does

- Renders message bubbles with alignment/grouping logic
- Handles emoji-only messages with special styling
- Renders reactions and read receipts
- Implements hover state + quick-react popover
- Implements emoji picker popover
- Handles right-click context menu (edit action)
- Renders send status icons (sending, sent, failed)
- Custom BubbleShape with corner radius logic
- String emoji detection (isEmojiOnly, isEmoji)

### Line-by-Line Breakdown

| Section | Lines | Purpose |
|---------|-------|---------|
| Props + state | 1–25 | Message data + hover/popover state |
| `body` | 44–76 | Main render: outgoing/incoming branching |
| Reaction handling | 78–81 | onToggleReaction callback |
| Context menu | 83–98 | Right-click menu for edit |
| Outgoing bubble | 100–161 | Emoji-only vs normal text layout |
| Outgoing content | 124–161 | Formatted body + timestamp + send status |
| Send status icon | 163–178 | Sending/sent/failed indicator |
| Incoming bubble | 182–246 | Avatar + VStack with sender name + bubble |
| Hover + popovers | 248–300 | bubbleWithHover builder, popover state |
| Smiley button | 292–299 | Hover button to trigger reactions |
| BubbleShape | 302–322 | Custom corner radius shape |
| String extension | 324–329 | Emoji detection |
| RightClickHandler | 331–351 | NSViewRepresentable for right-click |
| ContextMenuTarget | 353–360 | NSObject target for NSMenuItem action |
| Character.isEmoji | 362–367 | Unicode scalar emoji detection |

### Friction Points

1. **Multiple responsibilities mixed:**
   - Message rendering (layout, styling)
   - Reaction UI (popover, picker, quick bar)
   - Read receipts display
   - Edit action dispatch
   - Send status display

2. **Custom shape implementation** — BubbleShape duplicates corner-radius logic for group positions
   - Lines 302–322 are verbose path-drawing code

3. **NSView interop** — RightClickHandler and ContextMenuTarget are macOS-specific hacks
   - The edit action uses an NSObject singleton target (`ContextMenuTarget.shared`)
   - This is tightly coupled to AppKit and hard to test

4. **Global singleton access** — `RecentReactions.shared.recordReaction()`
   - Emoji recording happens inside the view, mixed with UI logic

5. **Complex conditional rendering** — `isEmojiOnly` changes layout significantly, adds complexity

**Deletion test:** Would extracting reactions into `ReactionHandlerView`, read receipts into `ReadReceiptRow`, and send status into `SendStatusIndicator` scatter complexity?

→ **Yes, it would scatter across multiple files**, but would improve **clarity and testability**:
- `ReactionHandlerView` could be unit-tested with mocks
- `SendStatusIndicator` is pure presentational
- Main `MessageBubbleView` would focus on layout

**Current state:** 367 lines is at the threshold where many would consider extracting sub-views. The view is **functional but dense.**

---

## 7. ADAPTER LIFECYCLE MANAGEMENT

### Listener Retention Pattern

**Critical pattern from CLAUDE.md:**
> *"SDK listener objects (room list, timeline, verification delegates) MUST be retained as properties on the adapter. If they're local variables, the Rust SDK will deallocate them and crash."*

This is implemented correctly throughout, e.g.:

```swift
// In MatrixSyncAdapter
private var entriesListener: NebRoomListEntriesListener?
private var entriesHandle: TaskHandle?

// In MatrixRoomAdapter
private var activeTimelines: [String: TimelineHandle] = [:]
private struct TimelineHandle {
    let room: Room
    let timeline: Timeline
    let listener: NebTimelineListener
    let listenerHandle: TaskHandle
}
```

**But there's potential for errors:**

1. **Leaked references in closures** — If a listener closure captures `self`, it could create retain cycles
2. **Task cancellation not guaranteed** — View models have `deinit` blocks to cancel tasks, but not all task handles might be cancelled
3. **No explicit lifecycle tests** — You can't test "listener was properly retained" without integration tests

### Task Cleanup Patterns

Scattered throughout:

```swift
// RoomListViewModel
deinit {
    syncTask?.cancel()
    for task in typingTasks.values { task.cancel() }
}

// TimelineViewModel
deinit {
    timelineTask?.cancel()
    typingTask?.cancel()
    typingDebounceTask?.cancel()
}

// VerificationViewModel
deinit {
    stateTask?.cancel()
    timeoutTask?.cancel()
}
```

**Issue:** These are necessary but fragile. If a new task is added and deinit isn't updated, it leaks.

**Deletion test:** Creating a `TaskBag` utility or `@Observable` macro to auto-cancel would:
- Concentrate cancellation logic
- Reduce boilerplate
- Make task leaks obvious (missing the new task from TaskBag)
- Result: **Scatter slightly due to adopting the pattern**, but **wins on safety**.

---

## 8. ERROR HANDLING PATTERNS

### Silent Failures Throughout

**Pattern:** `try?` without logging

**Examples:**

1. **MatrixAuthAdapter.login() — Crypto store conflict:**
   ```swift
   } catch {
       logger.error("Login failed: \(error.localizedDescription), clearing stores")
       clearSessionData()
       throw error  // ← Re-throws, good
   }
   ```
   ✓ Good: logs and re-throws

2. **MatrixSyncAdapter.convertAndEmit() — Room info fetch:**
   ```swift
   do {
       let info = try await room.roomInfo()
       isDirect = info.isDirect
       unread = info.numUnreadNotifications
   } catch {
       logger.warning("Failed to get room info for \(roomID): \(error.localizedDescription)")
   }
   ```
   ✓ Good: logs warning but doesn't fail the update

3. **MatrixRoomAdapter.timelineStream() — Room subscription:**
   ```swift
   if let rls = self.roomListServiceProvider() {
       try? await rls.subscribeToRooms(roomIds: [roomID])  // ← Silent failure
       logger.info("Subscribed to room \(roomID)")
   }
   ```
   ✗ Bad: `try?` swallows errors, then logs success even if subscription failed

4. **TimelineViewModel.sendMessage():**
   ```swift
   public func sendMessage(_ body: String) async {
       // ...
       do {
           try await roomService.sendMessage(roomID: roomID, body: trimmed)
       } catch {}  // ← Silent failure
   }
   ```
   ✗ Bad: swallows all errors, no logging, no user feedback

5. **TimelineViewModel.loadMore():**
   ```swift
   do {
       try await roomService.paginateBackwards(roomID: roomID, count: 50)
       try? await Task.sleep(for: .milliseconds(500))
   } catch {}  // ← Silent failure
   ```
   ✗ Bad: could fail silently

### Impact

- **Hard to debug** — Why didn't a message send? Why is the room list stale? No signals
- **No telemetry** — Can't track error rates or patterns
- **No user feedback** — Users don't know if operations failed
- **Untestable** — Can't write tests that verify "error was handled gracefully"

### Deletion Test: Would a `Result<T, Error>` type or error propagation scatter or concentrate?

If you changed signatures to:

```swift
public func sendMessage(roomID: String, body: String) async throws -> Void
```

Instead of silently catching:

```swift
do {
    try await roomService.sendMessage(roomID: roomID, body: trimmed)
    // Update UI to show success
} catch {
    // Update UI to show error
    errorMessage = error.localizedDescription
}
```

**Result:** → **Scatter**. Now every call site needs error handling. But **it's the right scatter** because errors become visible.

**Verdict:** Current error handling is **problematic**. Should either:
1. Log errors explicitly
2. Propagate errors to view model/view for user feedback
3. Retry with exponential backoff

---

## 9. GLOBAL/SINGLETON STATE

### AvatarImageCache.shared

**File:** `NebCore/Sources/NebCore/Services/AvatarImageCache.swift` (62 lines)

```swift
public final class AvatarImageCache: @unchecked Sendable {
    public static let shared = AvatarImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    private var inflight: [String: Task<PlatformImage?, Never>] = [:]
    private let lock = NSLock()
    private var clientProvider: (() -> Client?)?
}
```

**Used in:**
- `AppState.onLoggedIn()`: `AvatarImageCache.shared.setClientProvider(...)`
- `AvatarView.swift`: `await AvatarImageCache.shared.image(for: url)`

**Issue:** The clientProvider is set after login, but:
- If multiple logins happen, the provider is overwritten
- On logout, the provider isn't cleared (would still have stale client reference)
- Cache persists across logout (could leak avatars of users you were logged in as)

**Deletion test:** Pass cache as a dependency to views instead of using `.shared`?
- Would require threading it through the view hierarchy
- Each view would hold a reference
- Result: **Scatter**, but **improves testability** (can inject mock cache)

### RecentReactions.shared

**File:** `Neb/Views/Timeline/QuickReactBar.swift` (55 lines)

```swift
class RecentReactions {
    static let shared = RecentReactions()
    private let key = "recentReactions"
    private let maxCount = 20
    
    var list: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? EmojiData.defaultQuickReactions
    }
    
    func recordReaction(_ emoji: String) {
        // ... persist to UserDefaults
    }
}
```

**Used in:**
- `MessageBubbleView.react()`: `RecentReactions.shared.recordReaction(emoji)`
- `QuickReactBar`: `RecentReactions.shared.list`
- `EmojiPickerView`: indirectly

**Issue:** Persists to `UserDefaults` synchronously, no error handling

**Deletion test:** Passed as environment value instead?
- `@Environment(\.recentReactions) var recentReactions`
- Would require threading through view hierarchy
- Result: **Scatter, but cleaner**

### ContextMenuTarget.shared

**File:** `Neb/Views/Timeline/MessageBubbleView.swift` (353–360)

```swift
private class ContextMenuTarget: NSObject {
    static let shared = ContextMenuTarget()
    var onEdit: (() -> Void)?
    
    @objc func editMessage() {
        onEdit?()
    }
}
```

**Why this exists:** NSMenu requires a target for NSMenuItem actions. macOS requires the target to be an NSObject with an `@objc` method.

**Issue:** Shared global state, only one `onEdit` callback can be active at a time. Works because only one right-click menu is open, but fragile.

**Deletion test:** This is a workaround for macOS APIs. You can't easily delete it without changing the API interaction pattern.

---

## 10. SUMMARY: FRICTION BY SEVERITY

| Area | Severity | Type | Testability |
|------|----------|------|-----------|
| **Untested adapters** | High | Coverage gap | 0% |
| **Silent error handling** | High | Robustness | Implicit |
| **Hardcoded homeserver URL** | Medium | Configuration | Hardcoded |
| **SDK type conversion in adapters** | Medium | Maintainability | Not unit-tested |
| **Listener lifecycle (manual retention)** | Medium | Safety | Integration-tested only |
| **MessageBubbleView complexity** | Medium | Maintainability | Not unit-tested |
| **Shallow protocols (Typing, Notification)** | Low | Abstraction | Testable via mocks |
| **String-based IDs** | Low | Type safety | Accepted pattern |
| **AppState god object** | Low | Architecture | Acceptable for scope |
| **View model task cleanup** | Low | Robustness | Implicit |

---

## 11. ACTIONABLE RECOMMENDATIONS

### High Priority

1. **Extract TimelineEventConverter utility** (Concentrate)
   - Move `convertItem()` from MatrixRoomAdapter to a standalone module
   - Unit test against mock SDK types
   - Impact: ~50 lines extracted, fully testable

2. **Add error logging to silent failures** (Fix)
   - Review all `try? { ... } catch {}` patterns
   - Log at least the error description
   - Propagate errors to UI for user feedback (failed message send, failed read receipt)
   - Impact: Improve debuggability without changing APIs

3. **Extract homeserver URL from session** (Fix)
   - Load URL from stored `Session` instead of hardcoding
   - Update `AvatarImageCache` initialization in `onLoggedIn()`
   - Impact: Support multiple homeservers, fix avatar cache initialization

### Medium Priority

4. **Extract reaction handling from MessageBubbleView** (Scatter)
   - Create `ReactionBubble` sub-view
   - Extract `RecentReactions` access to parent
   - Impact: Reduce main view to 300 lines, improve clarity

5. **Add adapter integration tests** (Concentrate)
   - Test `MatrixSyncAdapter` delta processing
   - Test timeline event conversion with real SDK types (or mocked timeline items)
   - Impact: Catch regressions in SDK integration

6. **Unify task cancellation pattern** (Scatter)
   - Create `@Observable TaskBag` or similar
   - All tasks added to bag are cancelled in deinit
   - Impact: Reduce boilerplate, catch forgotten task cancellations

### Low Priority

7. **Consider typed value objects** (Scatter)
   - `struct RoomID: Hashable { let value: String }`
   - `struct UserID: Hashable { let value: String }`
   - Impact: Catch invalid IDs at compile time, but adds complexity

8. **Thread caches as dependencies** (Scatter)
   - Remove `AvatarImageCache.shared`, pass as `@Environment`
   - Remove `RecentReactions.shared`, pass as dependency
   - Impact: Improve testability, reduce implicit global state

---

## DELETION TEST SUMMARY

For each major module:

| Module | Delete It? | Complexity Scatters? | Verdict |
|--------|-----------|---------------------|---------|
| **MatrixAuthAdapter** | No | Would scatter | Keep: wraps session logic |
| **MatrixSyncAdapter** | No | Would scatter | Keep: concentrates delta processing |
| **MatrixRoomAdapter** | No | Would scatter | Keep: concentrates event conversion (needs refactor) |
| **MatrixCryptoAdapter** | No | Would scatter | Keep: state machine logic |
| **MatrixTypingAdapter** | No | Would concentrate slightly | Keep: maintains abstraction boundary |
| **MatrixNotificationAdapter** | Maybe | Would stay same | Thin: only wraps UNUserNotificationCenter |
| **TimelineViewModel** | No | Would scatter | Keep: but consider extracting typing logic |
| **RoomListViewModel** | No | Would scatter | Keep: subscription management is correct |
| **AppState** | No | Would re-materialize elsewhere | Keep: root coordinator pattern |
| **MessageBubbleView** | No | Would scatter across sub-views | Keep: but extract sub-components |

---

## CONCLUSION

Neb has **solid foundational architecture** (clear boundaries, testable view models, protocol-based adapters). The friction is mostly **incremental accumulation**:

1. **Coverage gaps** — adapters lack unit tests
2. **Error handling** — silently swallowing errors reduces debuggability
3. **View complexity** — MessageBubbleView (and verification views) are dense
4. **Configuration** — hardcoded homeserver URL limits flexibility
5. **SDK integration** — event conversion and lifecycle management are manual and fragile

These are **solvable problems**, not architectural failures. The codebase is well-positioned for the fixes.
