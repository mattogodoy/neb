# Avatars, Read Status & Message Redesign — Design Spec

## Overview

Redesign the timeline, sidebar, and message bubbles to match Element X quality. Three tightly coupled features implemented together: avatars throughout the app, read receipt / send status indicators, and a redesigned message layout with grouping and day separators.

## Data Model Changes

### NebMessage additions

```swift
public var senderAvatarURL: String?    // mxc:// URL
public var sendStatus: SendStatus      // .sending, .sent, .failed
public var readReceipts: [ReadReceipt] // who has read up to this message
```

### New types

```swift
public enum SendStatus: Equatable, Sendable {
    case sending
    case sent
    case failed
}

public struct ReadReceipt: Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let avatarURL: String?
}
```

### NebRoom additions

```swift
public var avatarURL: String?  // mxc:// URL for room or DM partner avatar
```

## Avatar System

### AvatarView (reusable SwiftUI component)

A single `AvatarView` used everywhere in the app. Parameters:
- `size: CGFloat` — diameter (32pt sidebar, 28pt timeline, 14pt read receipts)
- `name: String` — fallback display name (first character used as initial)
- `userID: String` — used for deterministic color hashing
- `avatarURL: String?` — optional mxc:// URL

Behavior:
1. Immediately show colored circle with initial letter
2. If `avatarURL` is set, load the image asynchronously
3. When image loads, crossfade from initial to image
4. If image fails to load, keep showing initial

### Color generation

Hash the Matrix user ID to an index into a fixed palette of 10 visually distinct colors. The same user ID always produces the same color. The palette is designed to work in both light and dark mode.

### Image loading

Convert mxc:// URLs to HTTP thumbnail URLs: `https://{homeserver}/_matrix/media/v3/thumbnail/{serverName}/{mediaId}?width=64&height=64&method=crop`

Cache loaded images in a `NSCache<NSString, NSImage>`-based singleton (`AvatarImageCache`) so images persist across view redraws without re-downloading. The cache is in-memory only — no disk persistence needed for avatars.

### Avatar sizes

| Context | Size |
|---|---|
| Sidebar room row | 32pt |
| Timeline (group, first in group) | 28pt |
| Read receipt indicator | 14pt |

### Where avatars appear

- **Sidebar**: every room row (room avatar, or DM partner's avatar)
- **Timeline (groups only)**: on the first message in a sender group
- **Read receipts**: tiny circles below the last message each user has read
- **DMs**: no avatars in timeline (implicit from context)

## Message Bubble Redesign

### Timestamp placement

Timestamp moves from below the bubble to inline at the end of the message text, rendered smaller (10pt) and muted. More compact, matches Element X.

### Message grouping

Consecutive messages from the same sender within 5 minutes are grouped:
- **First in group**: shows avatar (groups only) + colored username (groups only) + bubble with timestamp
- **Continuation**: just the bubble, aligned with the first message (indented past where the avatar would be in groups). Reduced top margin (2pt instead of 8pt).

Grouping breaks when:
- Different sender
- More than 5 minutes between messages
- Day boundary crossed

### Bubble shapes

- First message in a group (incoming): small top-left radius (2pt), other corners 12pt
- First message in a group (outgoing): small top-right radius (2pt), other corners 12pt
- Continuation messages: uniform 12pt radius on the bubble corner closest to the sender, 2pt on the other

### Group chat layout

Incoming first-in-group:
```
[28pt avatar] [colored username]
              [bubble with message ... 17:22]
```

Incoming continuation:
```
              [bubble with message ... 17:23]
```

Outgoing (always right-aligned, no avatar):
```
                        [bubble with message ... 18:30]
```

### DM layout

No avatars. No usernames. Just left/right bubbles with the same grouping logic for spacing.

Incoming:
```
[bubble with message ... 14:30]
```

Outgoing:
```
                        [bubble with message ... 14:32]
```

### Day separators

Centered pill inserted into the message list between messages from different calendar days.

Labels:
- Same day: "Today"
- Previous day: "Yesterday"
- Same week: weekday name (e.g. "Saturday")
- Older: full date (e.g. "May 20, 2026")

Rendered as: centered text with a subtle rounded-rect background.

## Read Receipts & Send Status

### Send status (outgoing messages only)

Derived from `EventTimelineItem.localSendState`:
- `nil` (remote event) → `.sent`
- `.notSentYet` → `.sending`
- `.sendingFailed` → `.failed`

Display inline after the timestamp:
- `.sending` — small spinner
- `.sent` — single gray checkmark "✓"
- `.failed` — red "!" icon

Once any read receipt exists on the message, the checkmark is removed — the tiny avatars replace it.

### Read receipt display

- Tiny avatar circles (14pt `AvatarView`) shown below and right-aligned to the message
- Stacked with -4pt overlap when multiple readers
- Maximum 3 avatars shown; if more, show "+N" text
- Only shown on the latest message each user has read (not on every message)
- Data source: `EventTimelineItem.readReceipts` dictionary from the SDK

### Populating read receipts in the adapter

The `NebTimelineListener.convertItem` method already has access to `event.readReceipts` (a `[String: Receipt]` dictionary). Extract user IDs and map to `ReadReceipt` structs. Display names and avatar URLs can be resolved from cached room member data.

## Sidebar Changes

### Room row redesign

- Replace the plain colored circle with `AvatarView` (real avatar + initial fallback)
- Add relative timestamp to the right of the room name ("10:15", "Fri", "May 20")
- Last message preview: "sender: message" for groups, just the message for DMs
- Unread badge stays the same

### Timestamp formatting

- Today: time only ("10:15")
- Yesterday: "Yesterday"
- This week: weekday name ("Fri")
- Older: short date ("May 20")

## Files Changed

### New files
- `Neb/Views/Common/AvatarView.swift` — reusable avatar component
- `NebCore/Sources/NebCore/Services/AvatarImageCache.swift` — NSCache-based image loader

### Modified files
- `NebCore/Sources/NebCore/Models/NebMessage.swift` — add senderAvatarURL, sendStatus, readReceipts
- `NebCore/Sources/NebCore/Models/NebRoom.swift` — add avatarURL
- `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift` — populate new fields from SDK
- `NebCore/Sources/NebCore/Adapters/MatrixSyncAdapter.swift` — populate room avatarURL
- `Neb/Views/Timeline/MessageBubbleView.swift` — complete rewrite
- `Neb/Views/Timeline/TimelineView.swift` — add day separators, grouping logic
- `Neb/Views/Sidebar/RoomRowView.swift` — avatars, timestamps, preview format
