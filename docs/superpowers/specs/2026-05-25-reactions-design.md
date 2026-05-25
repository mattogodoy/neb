# Emoji Reactions — Design Spec

## Overview

Add emoji reactions to messages in Neb. Users can view existing reactions, add reactions via a three-step interaction (hover → quick bar → full picker), and toggle reactions on/off.

## Data Model

### NebMessage addition

```swift
public var reactions: [NebReaction]
```

### New type

```swift
public struct NebReaction: Equatable, Sendable {
    public let emoji: String
    public let count: Int
    public let senderIDs: [String]
    public let includesMe: Bool
}
```

### RoomServiceProtocol addition

```swift
func toggleReaction(roomID: String, eventID: String, emoji: String) async throws
```

### SDK mapping

The SDK's `MsgLikeContent.reactions` is a `[Reaction]` where each `Reaction` has:
- `key: String` — the emoji
- `senders: [ReactionSenderData]` — each with `senderId: String`

Map to `[NebReaction]` in `convertItem`, comparing each sender against `myUserID` to set `includesMe`.

The SDK's `Timeline.toggleReaction(itemId:key:)` adds or removes a reaction. It takes an `EventOrTransactionId` and the emoji string.

## Reaction Display

A horizontal row of compact pills shown below the message bubble (above read receipts if present):

- Each pill shows: emoji (14pt) + count (11pt, only if > 1)
- Pills with `includesMe == true` have an accent-color tinted background
- Clicking a pill calls `toggleReaction` (adds if not reacted, removes if already reacted)
- A small "+" pill at the end opens the full emoji picker
- The row wraps if there are many reactions (using `FlowLayout` or wrapping `HStack`)
- Always left-aligned below the bubble for both incoming and outgoing messages
- Compact sizing — small padding, the bar should feel lightweight

## Adding Reactions — Three-Step Flow

### Step 1: Hover hint

When the mouse hovers over a message, a small monochrome smiley face icon (☺) appears at the top-right corner of the bubble. Disappears when the mouse leaves.

### Step 2: Quick react bar

Clicking the smiley opens a floating pill bar above the message:
- Shows 6 emoji from the user's recent reactions (defaults: 👍 ❤️ 😂 😮 😢 🙏)
- A "+" button at the end opens the full picker (Step 3)
- Clicking any emoji reacts immediately and dismisses the bar
- Dismisses when clicking outside

### Step 3: Full emoji picker

Clicking "+" opens a popover anchored to the message:
- **Category tabs** at the top: Recent, Smileys & People, Animals & Nature, Food & Drink, Travel & Places, Activities, Objects, Symbols, Flags
- **Search bar** below the tabs — filters emoji by name
- **Recent reactions** section in the Recent tab showing the user's most recently used emoji
- **Emoji grid** — 8 columns, scrollable, organized by active category
- Clicking an emoji reacts and closes the picker

### Right-click

A "React..." context menu item on messages opens the full picker directly (Step 3).

## Recent Reactions

Track the last 20 emoji the user has reacted with. Stored in `UserDefaults` under key `"recentReactions"` as a `[String]` array. New reactions are prepended; duplicates are moved to the front. The quick bar shows the first 6 from this list.

Default list (before any user reactions): `["👍", "❤️", "😂", "😮", "😢", "🙏"]`

## Emoji Data

Hardcoded Unicode arrays organized by category. No external dependencies. The emoji set covers standard Unicode emoji (Emoji 15.0). Each emoji entry is just the Unicode string — names for search are derived from a parallel array of keywords.

## Files Changed

### New files
- `NebCore/Sources/NebCore/Models/NebReaction.swift` — NebReaction struct
- `Neb/Views/Timeline/ReactionBarView.swift` — reaction pills below messages
- `Neb/Views/Timeline/QuickReactBar.swift` — floating 6-emoji bar on click
- `Neb/Views/Common/EmojiPickerView.swift` — full emoji picker popover
- `Neb/Views/Common/EmojiData.swift` — hardcoded emoji arrays by category

### Modified files
- `NebCore/Sources/NebCore/Models/NebMessage.swift` — add reactions field
- `NebCore/Sources/NebCore/Services/RoomServiceProtocol.swift` — add toggleReaction method
- `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift` — implement toggleReaction, populate reactions in convertItem
- `NebCore/Tests/NebCoreTests/Mocks/MockRoomService.swift` — add toggleReaction mock
- `Neb/Views/Timeline/MessageBubbleView.swift` — add reaction bar, hover smiley, quick react bar, right-click menu
