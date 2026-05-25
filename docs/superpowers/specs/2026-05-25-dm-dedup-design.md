# DM Deduplication — Combined Timeline

## Problem

Matrix allows multiple DM rooms with the same user. Other clients (Element, etc.) can create new DM rooms at any time. Neb shows all of them as separate entries in the sidebar, which is confusing — the user expects one conversation per person.

## Approach

View-model-layer grouping with combined timeline (Approach B). No changes to service protocols, adapters, or the SDK layer. The underlying Matrix rooms stay separate; Neb presents them as one.

## Design

### Room List Grouping

`RoomListViewModel` groups DM rooms by `directUserID` when computing `directMessages`.

For each unique `directUserID`:
- **Primary room**: the room with the most recent `lastMessageTimestamp`. If timestamps are equal or nil, fall back to highest `unreadCount`, then first by room ID (deterministic).
- **Sidebar entry**: uses the primary room's name and avatar. Last message preview and timestamp are taken from whichever room in the group has the most recent `lastMessageTimestamp` (may differ from the primary).
- **Unread count**: summed across all rooms in the group.

The view model exposes:
- `roomIDs(for room: NebRoom) -> [String]` — returns all room IDs grouped under that DM entry, primary first. For non-DM rooms, returns `[room.id]`.

Internal state:
- `dmGroups: [String: [String]]` — maps `directUserID` to `[roomID]`, recomputed on each `allRooms` update.

The `groups` computed property (non-DM rooms) is unchanged.

### Combined Timeline

`TimelineViewModel` changes from single room to multi-room:

- `init(roomIDs: [String], roomService: RoomServiceProtocol)` replaces `init(roomID:roomService:)`.
- `primaryRoomID`: first element of `roomIDs` — used for sending messages.
- Subscribes to `timelineStream` for each room ID.
- Merges all messages into a single `[NebMessage]` sorted by `timestamp`.
- `NebMessage.roomID` already exists, so each message retains its source room.

Operations:
- **Send message**: goes to `primaryRoomID`.
- **Send read receipt**: fires on the room that owns the last message (`message.roomID`).
- **Paginate backwards**: paginates on all room IDs so older history from any room loads in.
- **Toggle reaction**: uses `message.roomID` to target the correct room.

For non-DM rooms (single-element `roomIDs` array), behavior is identical to current.

### Notifications and Unread Counts

- The grouped sidebar entry shows summed `unreadCount` across all rooms for that user.
- `postNotificationsForNewMessages` continues to iterate per-room internally — notifications fire per room as before.
- The dock badge (`totalUnreadCount`) is unchanged — it sums all rooms, and grouping doesn't affect the total since unreads aren't double-counted (each room has its own count).

### Wiring

`AppState` requires no changes. The view layer passes `roomIDs` from `RoomListViewModel.roomIDs(for:)` when constructing `TimelineViewModel`.

No changes to:
- `RoomServiceProtocol`
- `MatrixRoomAdapter`
- `MatrixSyncAdapter`
- `SyncServiceProtocol`
- `NebRoom` model
- `NebMessage` model

### Files Changed

| File | Change |
|------|--------|
| `NebCore/Sources/NebCore/ViewModels/RoomListViewModel.swift` | Add `dmGroups` state, grouping logic in `directMessages`, `roomIDs(for:)` method |
| `NebCore/Sources/NebCore/ViewModels/TimelineViewModel.swift` | Accept `[String]` room IDs, merge multiple timeline streams, route operations by room |
| `Neb/Views/Timeline/TimelineView.swift` | Pass `roomIDs` instead of single `roomID` when creating `TimelineViewModel` |
| `Neb/Views/Sidebar/*.swift` | Pass grouped room to timeline (if sidebar creates the view model) |

### Testing

**RoomListViewModelTests:**
- Multiple DM rooms with same `directUserID` -> `directMessages` returns one entry per user.
- Primary room selection: most recent timestamp wins.
- Unread count is summed across grouped rooms.
- `roomIDs(for:)` returns all room IDs, primary first.
- Non-DM rooms are unaffected.

**TimelineViewModelTests:**
- Messages from two room IDs appear interleaved by timestamp.
- `sendMessage` goes to the primary room ID.
- `toggleReaction` uses the message's own `roomID`.
- Single room ID behaves identically to current behavior.

### Edge Cases

- **DM room with nil `directUserID`**: not grouped, shown as-is (defensive — shouldn't happen in practice).
- **User leaves one of the grouped rooms**: SDK removes it from the room list, grouping naturally shrinks.
- **New DM room appears mid-session**: next room list update recomputes groups, new room joins the existing group.
- **All rooms for a user have no messages**: primary is chosen by room ID sort order. Timeline is empty.
