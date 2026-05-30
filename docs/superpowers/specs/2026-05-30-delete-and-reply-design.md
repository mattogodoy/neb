# Delete Message and Reply Feature

Two features in one spec since they share the same UI surface (context menu, message bubble).

---

## Feature 1: Delete Message (#10)

### Summary

Right-click an outgoing message > "Delete" > confirmation dialog > redacts the message for everyone via SDK. Redacted messages render as "[message deleted]" in the timeline.

### Scope

- Single message delete only (no multi-select)
- Redact for everyone (server-side, no local-only delete)
- Own messages only

### Existing Infrastructure

- `TimelineProtocol.delete(roomID:eventID:reason:)` -- protocol method exists
- `Room.delete()` -- calls SDK's `timeline.redactEvent()`
- `NebDatabase.redactMessage(eventID:)` -- clears body and formattedBody
- `MsgLikeKind.redacted` -- SDK enum case for redacted events (currently ignored by listener)

### Changes

**NebCore:**
1. **NebTimelineListener** (Room.swift) -- handle `.redacted` case in `processItem()`: call `database.redactMessage(eventID:)` to clear body/formattedBody in the local DB.

**App:**
2. **MessageBubbleView** -- add "Delete" to right-click context menu (shown for outgoing messages only). Accept `onDelete` callback.
3. **TimelineView** -- show confirmation alert on delete. On confirm, call `viewModel.deleteMessage(eventID:)`.
4. **TimelineViewModel** -- add `deleteMessage(eventID:)` method that calls `roomService.delete()`.

### UI Behavior

- Messages with empty body (redacted) render as italic "[message deleted]" in secondary color, no bubble background, no reactions, no read receipts.
- Confirmation dialog: "Delete this message? This can't be undone." with Cancel / Delete (destructive).

---

## Feature 2: Reply (#13)

### Summary

Right-click a message > "Reply" (or double-click any message) sets the composer into reply mode. A reply preview bar shows above the text field. On send, calls `Room.sendReply()`. Reply messages display a quoted preview above the bubble body. Clicking the quote scrolls to and temporarily highlights the original message.

### Scope

- Reply to any message (own or others)
- Quote preview in bubble (sender name + truncated body)
- Scroll-to-original on quote click
- Double-click on a message row prepares reply

### Existing Infrastructure

- `TimelineProtocol.sendReply(roomID:body:replyToEventID:)` -- protocol method exists
- `Room.sendReply()` -- calls SDK's `timeline.sendReply()`
- `MsgLikeContent.inReplyTo: InReplyToDetails?` -- SDK provides reply details:
  - `eventId() -> String`
  - `event() -> EmbeddedEventDetails` with `.ready(content:, sender:, senderProfile:, ...)` or `.unavailable`

### Changes

**NebCore:**
1. **MessageRecord** -- add `replyToEventID: String?` column.
2. **NebDatabase** -- schema migration v5: add column `replyToEventID` to messages table. Update `insertMessage()` and `fetchMessages()` to handle new column.
3. **NebMessage** -- add `replyToEventID: String?`, `replyToSenderName: String?`, `replyToBody: String?`.
4. **NebTimelineListener** (Room.swift) -- extract `msgLike.inReplyTo?.eventId()` and the embedded event details (sender name, body). Store `replyToEventID` in the MessageRecord. Pass reply display data through to the UI.
5. **TimelineViewModel** -- add `replyingToMessage: NebMessage?`, `startReply(message:)`, `cancelReply()`. Update `sendMessage()` to call `sendReply()` when `replyingToMessage` is set.
6. **NebDatabase** -- update `toNebMessage()` / `observeMessages()` to join reply info: look up the replied-to message's sender and body from the messages + profiles tables.

**App:**
7. **MessageBubbleView** -- add "Reply" to right-click context menu. Accept `onReply` callback. Render reply quote above bubble body when `replyToSenderName` / `replyToBody` exist. Accept `onQuoteTap` callback for scroll-to-original.
8. **MessageComposerView** -- show reply preview bar when `viewModel.replyingToMessage` is set (sender name, truncated body, cancel button).
9. **TimelineView** -- wire reply callbacks. On quote tap, scroll to and temporarily highlight the original message. On double-click, start reply. Pass `onReply` and `onQuoteTap` to MessageBubbleView.

### Reply Quote UI

Compact bar above the message body inside the bubble:
- 2pt accent-color left border
- Sender name (bold, small)
- Body preview (1 line, truncated, secondary color)

### Reply Preview in Composer

Horizontal bar above the text field:
- "Replying to [sender name]" label
- Truncated body preview
- X button to cancel reply

### Double-Click Behavior

- Double-click on any message row (the whole row, not just the bubble) calls `onReply(message)`.
- This sets `viewModel.replyingToMessage = message` and focuses the composer.

### Scroll-to-Original

When the user clicks the reply quote in a bubble:
- Scroll to the original message via ScrollViewReader
- Temporarily highlight it (reuse the search highlight style -- accent-color left border)
- Highlight fades after 1.5 seconds

### Edge Cases

- **Replied-to message not loaded** -- show "Original message" as placeholder if the message isn't in the local DB yet.
- **Replied-to message redacted** -- show "[message deleted]" as the quoted body.
- **Reply to a reply** -- show the direct parent only, no chain.
