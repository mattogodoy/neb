# Delete Message & Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add right-click delete (redact) for own messages and reply feature with double-click, quote preview, and scroll-to-original.

**Architecture:** Delete uses existing `Room.delete()` + `NebDatabase.redactMessage()`. Reply adds `replyToEventID` column (migration v5), extracts reply info from SDK's `MsgLikeContent.inReplyTo`, and renders quote previews in the bubble and composer.

**Tech Stack:** SwiftUI, NebCore (GRDB, MatrixRustSDK)

---

## Phase 1: Delete Message

### Task 1: Handle redacted events in NebTimelineListener

**Files:**
- Modify: `NebCore/Sources/NebCore/Room/Room.swift:628-675`

- [ ] **Step 1: Add `.redacted` case to `processItem()`**

In `Room.swift`, the `NebTimelineListener.processItem()` method has a switch on `msgLike.kind` (around line 628). Currently:

```swift
switch msgLike.kind {
case .message(let msgContent):
    // ... insert/update message
case .unableToDecrypt:
    // ... insert placeholder
default:
    return
}
```

Add a `.redacted` case before the `default`. Replace lines 628-675 section:

```swift
switch msgLike.kind {
case .message(let msgContent):
    // existing message handling unchanged...

case .unableToDecrypt:
    // existing handling unchanged...

case .redacted:
    try? database.redactMessage(eventID: eventID)

default:
    return
}
```

The key change: just add `case .redacted: try? database.redactMessage(eventID: eventID)` before `default: return`.

- [ ] **Step 2: Build NebCore**

Run: `cd NebCore && swift build`

- [ ] **Step 3: Run tests**

Run: `cd NebCore && swift test`

- [ ] **Step 4: Commit**

```bash
git add NebCore/Sources/NebCore/Room/Room.swift
git commit -m "feat: handle redacted events in timeline listener"
```

---

### Task 2: Add delete method to TimelineViewModel and render redacted messages

**Files:**
- Modify: `Neb/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add deleteMessage method**

After the `clearSearch()` method in `TimelineViewModel`, add:

```swift
public func deleteMessage(eventID: String) async {
    do {
        try await roomService.delete(roomID: roomID, eventID: eventID, reason: nil)
    } catch {
        logger.error("Failed to delete message \(eventID) in \(self.roomID): \(error)")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/ViewModels/TimelineViewModel.swift
git commit -m "feat: add deleteMessage to TimelineViewModel"
```

---

### Task 3: Add Delete to context menu and render redacted bubbles

**Files:**
- Modify: `Neb/Views/Timeline/MessageBubbleView.swift`
- Modify: `Neb/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add onDelete callback and delete context menu item to MessageBubbleView**

In `MessageBubbleView`, add a new property after `var isHighlighted`:

```swift
var onDelete: (() -> Void)?
```

In `showContextMenu()`, add a "Delete" item after the Edit section (before the `if !menu.items.isEmpty` check):

```swift
if message.isOutgoing && message.sendStatus == .sent {
    let deleteItem = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
    deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
    menu.addItem(deleteItem)
    deleteItem.target = ContextMenuTarget.shared
    deleteItem.action = #selector(ContextMenuTarget.deleteMessage)
    ContextMenuTarget.shared.onDelete = { [onDelete] in onDelete?() }
}
```

Add `onDelete` to the `ContextMenuTarget` class:

```swift
var onDelete: (() -> Void)?

@objc func deleteMessage() {
    onDelete?()
}
```

- [ ] **Step 2: Render redacted messages**

In the `renderedBody` computed property (around line 23), add a check at the top for empty body (redacted):

```swift
private var renderedBody: Text {
    if message.body.isEmpty {
        return Text("[message deleted]")
            .italic()
    }
    if let attributed = HTMLRenderCache.shared.render(message.formattedBody) {
        return Text(attributed)
    }
    return Text(message.body)
}
```

Do the same for `renderedBodyOutgoing` (around line 30):

```swift
private var renderedBodyOutgoing: Text {
    if message.body.isEmpty {
        return Text("[message deleted]")
            .italic()
    }
    if let attributed = HTMLRenderCache.shared.render(message.formattedBody, foregroundColor: .white) {
        return Text(attributed)
    }
    return Text(message.body)
}
```

- [ ] **Step 3: Wire onDelete in TimelineView**

In `TimelineView`, add a `@State` for the delete confirmation:

```swift
@State private var messageToDelete: NebMessage?
```

In the `MessageBubbleView` init inside `ForEach`, add the `onDelete` parameter:

```swift
onDelete: message.isOutgoing ? {
    messageToDelete = message
} : nil
```

Add a confirmation alert after the existing `.sheet(isPresented: $showVerification)`:

```swift
.alert("Delete Message", isPresented: Binding(
    get: { messageToDelete != nil },
    set: { if !$0 { messageToDelete = nil } }
)) {
    Button("Cancel", role: .cancel) { messageToDelete = nil }
    Button("Delete", role: .destructive) {
        if let msg = messageToDelete {
            Task { await viewModel.deleteMessage(eventID: msg.id) }
        }
        messageToDelete = nil
    }
} message: {
    Text("Delete this message? This can't be undone.")
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add Neb/Views/Timeline/MessageBubbleView.swift Neb/Views/Timeline/TimelineView.swift
git commit -m "feat: add delete to context menu with confirmation and redacted rendering"
```

---

## Phase 2: Reply Feature

### Task 4: Add replyToEventID to MessageRecord + migration v5

**Files:**
- Modify: `NebCore/Sources/NebCore/Database/MessageRecord.swift`
- Modify: `NebCore/Sources/NebCore/Database/NebDatabase.swift`

- [ ] **Step 1: Add replyToEventID to MessageRecord**

In `MessageRecord`, add a new property after `transactionID`:

```swift
public var replyToEventID: String?
```

Update the init to accept it:

```swift
public init(
    eventID: String,
    roomID: String,
    senderID: String,
    body: String,
    formattedBody: String? = nil,
    timestamp: Double,
    isEdited: Bool = false,
    sendStatus: String = "sent",
    transactionID: String? = nil,
    replyToEventID: String? = nil
) {
    self.eventID = eventID
    self.roomID = roomID
    self.senderID = senderID
    self.body = body
    self.formattedBody = formattedBody
    self.timestamp = timestamp
    self.isEdited = isEdited
    self.sendStatus = sendStatus
    self.transactionID = transactionID
    self.replyToEventID = replyToEventID
}
```

- [ ] **Step 2: Add migration v5**

In `NebDatabase.swift`, after the `v4_members_table` migration (around line 732), add:

```swift
migrator.registerMigration("v5_reply_column") { db in
    try db.alter(table: "messages") { t in
        t.add(column: "replyToEventID", .text)
    }
}
```

- [ ] **Step 3: Update insertMessage to include replyToEventID**

In `NebDatabase.insertMessage()` (around line 30), update the SQL and arguments:

```swift
public func insertMessage(_ message: MessageRecord) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO messages
                    (eventID, roomID, senderID, body, formattedBody, timestamp,
                     isEdited, sendStatus, transactionID, replyToEventID)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                message.eventID, message.roomID, message.senderID,
                message.body, message.formattedBody, message.timestamp,
                message.isEdited, message.sendStatus, message.transactionID,
                message.replyToEventID
            ]
        )
    }
}
```

- [ ] **Step 4: Update MessageWithProfile to include reply info**

In `MessageWithProfile`, add fields for the replied-to message:

```swift
public struct MessageWithProfile: FetchableRecord, Sendable {
    public let message: MessageRecord
    public let displayName: String?
    public let avatarURL: String?
    public let replyToSenderName: String?
    public let replyToBody: String?

    public init(row: Row) throws {
        message = try MessageRecord(row: row)
        displayName = row["displayName"]
        avatarURL = row["avatarURL"]
        replyToSenderName = row["replyToSenderName"]
        replyToBody = row["replyToBody"]
    }
}
```

- [ ] **Step 5: Update fetch and observation queries to join reply info**

In `NebDatabase.fetchMessages()` (around line 145), update the SQL to left-join the replied-to message:

```swift
public func fetchMessages(roomID: String, limit: Int) throws -> [MessageWithProfile] {
    try dbQueue.read { db in
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT messages.*,
                       profiles.displayName,
                       profiles.avatarURL,
                       rp.displayName AS replyToSenderName,
                       rm.body AS replyToBody
                FROM messages
                LEFT JOIN profiles ON messages.senderID = profiles.userID
                LEFT JOIN messages rm ON messages.replyToEventID = rm.eventID
                LEFT JOIN profiles rp ON rm.senderID = rp.userID
                WHERE messages.roomID = ?
                ORDER BY messages.timestamp ASC
                LIMIT ?
                """,
            arguments: [roomID, limit]
        )
        return try rows.map { try MessageWithProfile(row: $0) }
    }
}
```

Update `messagesObservation()` (around line 328) with the same SQL:

```swift
public func messagesObservation(roomID: String, limit: Int = 50) -> ValueObservation<ValueReducers.Fetch<[MessageWithProfile]>> {
    ValueObservation.tracking { db in
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT messages.*,
                       profiles.displayName,
                       profiles.avatarURL,
                       rp.displayName AS replyToSenderName,
                       rm.body AS replyToBody
                FROM messages
                LEFT JOIN profiles ON messages.senderID = profiles.userID
                LEFT JOIN messages rm ON messages.replyToEventID = rm.eventID
                LEFT JOIN profiles rp ON rm.senderID = rp.userID
                WHERE messages.roomID = ?
                ORDER BY messages.timestamp ASC
                LIMIT ?
                """,
            arguments: [roomID, limit]
        )
        return try rows.map { try MessageWithProfile(row: $0) }
    }
}
```

- [ ] **Step 6: Build and test NebCore**

Run: `cd NebCore && swift build && swift test`

- [ ] **Step 7: Commit**

```bash
git add NebCore/Sources/NebCore/Database/MessageRecord.swift NebCore/Sources/NebCore/Database/MessageWithProfile.swift NebCore/Sources/NebCore/Database/NebDatabase.swift
git commit -m "feat: add replyToEventID column with migration v5 and reply joins"
```

---

### Task 5: Add reply fields to NebMessage + extract reply from SDK

**Files:**
- Modify: `NebCore/Sources/NebCore/Models/NebMessage.swift`
- Modify: `NebCore/Sources/NebCore/Room/Room.swift`
- Modify: `Neb/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add reply fields to NebMessage**

In `NebMessage`, add after `isEmojiOnly`:

```swift
public var replyToEventID: String?
public var replyToSenderName: String?
public var replyToBody: String?
```

Update the init to accept them (add after `isEmojiOnly: Bool = false`):

```swift
replyToEventID: String? = nil,
replyToSenderName: String? = nil,
replyToBody: String? = nil
```

And in the init body:

```swift
self.replyToEventID = replyToEventID
self.replyToSenderName = replyToSenderName
self.replyToBody = replyToBody
```

- [ ] **Step 2: Extract replyToEventID from SDK in NebTimelineListener**

In `Room.swift`, in `NebTimelineListener.processItem()`, in the `.message(let msgContent)` case (around line 629), after extracting `formattedBody`, add:

```swift
let replyToEventID = msgLike.inReplyTo?.eventId()
```

Then update the `MessageRecord` creation (around line 641) to include it:

```swift
let record = MessageRecord(
    eventID: eventID,
    roomID: roomID,
    senderID: event.sender,
    body: body,
    formattedBody: formattedBody,
    timestamp: timestamp,
    isEdited: isEdited,
    sendStatus: "sent",
    replyToEventID: replyToEventID
)
```

- [ ] **Step 3: Update TimelineViewModel.toNebMessage to pass reply data**

In `TimelineViewModel.toNebMessage()`, update the `NebMessage` init to include reply fields:

```swift
return NebMessage(
    id: m.eventID,
    roomID: m.roomID,
    senderID: m.senderID,
    senderDisplayName: row.displayName ?? m.senderID,
    senderAvatarURL: row.avatarURL,
    body: m.body,
    formattedBody: m.formattedBody,
    timestamp: Date(timeIntervalSince1970: m.timestamp),
    isOutgoing: isOutgoing,
    sendStatus: sendStatus,
    readReceipts: [],
    reactions: [],
    isEdited: m.isEdited,
    isEditable: isOutgoing && m.sendStatus == "sent",
    isEmojiOnly: m.body.isEmojiOnly,
    replyToEventID: m.replyToEventID,
    replyToSenderName: row.replyToSenderName,
    replyToBody: row.replyToBody
)
```

- [ ] **Step 4: Build**

Run: `cd NebCore && swift build`
Then: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add NebCore/Sources/NebCore/Models/NebMessage.swift NebCore/Sources/NebCore/Room/Room.swift Neb/ViewModels/TimelineViewModel.swift
git commit -m "feat: extract reply info from SDK and pass through to NebMessage"
```

---

### Task 6: Add reply state to TimelineViewModel

**Files:**
- Modify: `Neb/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add reply state and methods**

After `editingMessage` property, add:

```swift
public var replyingToMessage: NebMessage?
```

After `deleteMessage()`, add:

```swift
public func startReply(message: NebMessage) {
    replyingToMessage = message
}

public func cancelReply() {
    replyingToMessage = nil
}
```

- [ ] **Step 2: Update sendMessage to use sendReply when replying**

Update the `sendMessage()` method to check for `replyingToMessage`:

```swift
public func sendMessage(_ body: String) async {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    stopTyping()
    let replyTo = replyingToMessage
    replyingToMessage = nil
    do {
        if let replyTo {
            try await roomService.sendReply(roomID: roomID, body: trimmed, replyToEventID: replyTo.id)
        } else {
            try await roomService.send(roomID: roomID, body: trimmed)
        }
    } catch { logger.error("Failed to send message in \(self.roomID): \(error)") }
}
```

- [ ] **Step 3: Commit**

```bash
git add Neb/ViewModels/TimelineViewModel.swift
git commit -m "feat: add reply state and sendReply integration to TimelineViewModel"
```

---

### Task 7: Add Reply to context menu, reply quote in bubble, reply preview in composer

**Files:**
- Modify: `Neb/Views/Timeline/MessageBubbleView.swift`
- Modify: `Neb/Views/Timeline/MessageComposerView.swift`
- Modify: `Neb/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add onReply and onQuoteTap callbacks to MessageBubbleView**

After `onDelete`:

```swift
var onReply: (() -> Void)?
var onQuoteTap: ((String) -> Void)?
```

In `showContextMenu()`, add a "Reply" item. This goes before the edit/delete items (reply works on any message, not just your own). Add at the top of the method, before the edit check:

```swift
let replyItem = NSMenuItem(title: "Reply", action: nil, keyEquivalent: "")
replyItem.image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: nil)
menu.addItem(replyItem)
replyItem.target = ContextMenuTarget.shared
replyItem.action = #selector(ContextMenuTarget.replyToMessage)
ContextMenuTarget.shared.onReply = { [onReply] in onReply?() }
```

Add to `ContextMenuTarget`:

```swift
var onReply: (() -> Void)?

@objc func replyToMessage() {
    onReply?()
}
```

Remove the `if !menu.items.isEmpty` guard since the Reply item is always added, so the menu is never empty.

- [ ] **Step 2: Add reply quote view in MessageBubbleView**

Add a private computed property for the reply quote:

```swift
@ViewBuilder
private var replyQuoteView: some View {
    if let senderName = message.replyToSenderName {
        Button(action: {
            if let replyID = message.replyToEventID {
                onQuoteTap?(replyID)
            }
        }) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(message.replyToBody ?? "[message deleted]")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 6)
                .padding(.vertical, 2)
            }
        }
        .buttonStyle(.plain)
    }
}
```

Insert this quote view inside the bubble content. In `outgoingBubbleContent`, inside the non-emoji else branch, before `renderedBodyOutgoing`, add:

```swift
VStack(alignment: .trailing, spacing: 2) {
    replyQuoteView
    // existing HStack with renderedBodyOutgoing...
}
```

In the incoming non-emoji branch, before `renderedBody`, add:

```swift
VStack(alignment: .leading, spacing: 2) {
    replyQuoteView
    // existing HStack with renderedBody...
}
```

- [ ] **Step 3: Add double-click handler to MessageBubbleView**

In the `bubbleWithHover` method, add `.onTapGesture(count: 2)` to the content wrapper:

```swift
.onTapGesture(count: 2) {
    onReply?()
}
```

Place this before the `.contentShape(Rectangle())` modifier.

- [ ] **Step 4: Add reply preview bar to MessageComposerView**

In `MessageComposerView`, after the editing indicator `if` block (around line 21-40), add:

```swift
if let replyMsg = viewModel.replyingToMessage {
    HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 28)
        VStack(alignment: .leading, spacing: 1) {
            Text("Replying to \(replyMsg.senderDisplayName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(replyMsg.body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        Spacer()
        Button(action: { viewModel.cancelReply() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 2)
}
```

- [ ] **Step 5: Wire reply callbacks in TimelineView**

In the `MessageBubbleView` init inside `ForEach`, add:

```swift
onReply: {
    viewModel.startReply(message: message)
},
onQuoteTap: { originalID in
    scrollToAndHighlight(originalID, with: proxy)
}
```

Note: `proxy` must be in scope from `ScrollViewReader`. The `onQuoteTap` closure needs access to the scroll proxy. Since the `ForEach` is inside `ScrollViewReader { proxy in`, this is fine.

Add a `@State` for the temporary highlight:

```swift
@State private var temporaryHighlightID: String?
```

Add a helper method:

```swift
private func scrollToAndHighlight(_ messageID: String, with proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(messageID, anchor: .center)
    }
    temporaryHighlightID = messageID
    Task {
        try? await Task.sleep(for: .seconds(1.5))
        if temporaryHighlightID == messageID {
            temporaryHighlightID = nil
        }
    }
}
```

Update the `isHighlighted` parameter in `MessageBubbleView` to also check `temporaryHighlightID`:

```swift
isHighlighted: message.id == viewModel.highlightedMessageID || message.id == temporaryHighlightID
```

- [ ] **Step 6: Build**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 7: Commit**

```bash
git add Neb/Views/Timeline/MessageBubbleView.swift Neb/Views/Timeline/MessageComposerView.swift Neb/Views/Timeline/TimelineView.swift
git commit -m "feat: reply context menu, quote in bubble, preview in composer, double-click to reply"
```

---

### Task 8: Final build and test

- [ ] **Step 1: Full build**

```bash
xcodegen generate
xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

- [ ] **Step 2: Run NebCore tests**

```bash
cd NebCore && swift test
```

- [ ] **Step 3: Commit plan**

```bash
git add -f docs/superpowers/plans/2026-05-30-delete-and-reply.md
git commit -m "docs: delete and reply implementation plan"
```
