# In-Room Message Search

## Summary

Cmd+F opens a find bar inside the timeline view for the currently selected room. The user types a query, FTS5 returns matching event IDs, and the timeline scrolls to matches with up/down navigation. Esc closes the bar.

## Scope

- In-room search only (no cross-room search)
- Jump-between-matches pattern (Xcode-style, not filter-in-place)
- The sidebar search bar continues to filter rooms by name -- unchanged

## Existing Infrastructure

Everything in NebCore is already built:

- **`SearchProtocol`** -- `func search(query: String, roomID: String) async throws -> [SearchResult]`
- **`NebDatabase.search()`** -- FTS5 MATCH query over `messages_fts`, returns up to 100 results sorted by timestamp DESC
- **`Room`** adapter conforms to `SearchProtocol` -- passthrough to database
- **`SearchResult`** -- `eventID`, `roomID`, `senderID`, `body`, `timestamp`
- **FTS5 schema** -- external content table on `messages.body` with insert/delete/update triggers
- **Test coverage** -- `fts5Search()` in NebDatabaseTests

No changes needed in NebCore.

## UI Design

### Find Bar

Horizontal bar at the top of `TimelineView`, above the scroll view. Shown when `isSearching` is true.

```
┌─────────────────────────────────────────────────────┐
│ 🔍 [search text field        ]  3 of 12  ▲  ▼  ✕  │
└─────────────────────────────────────────────────────┘
```

- **Text field** -- placeholder "Search messages", focused on appear
- **Match count** -- "N of M" label (e.g. "3 of 12"), hidden when no query
- **Up/down chevrons** -- navigate between matches (wraps around)
- **Close button** -- clears search and hides the bar
- Styled with `.bar` material background, consistent with `ConnectionBanner`

### Keyboard Shortcuts

- **Cmd+F** -- toggle find bar (open if closed, focus if open)
- **Enter / Cmd+G** -- next match
- **Shift+Enter / Cmd+Shift+G** -- previous match
- **Esc** -- close find bar

### Match Highlighting

- The message bubble containing the current match gets a subtle visual indicator (e.g. a colored leading border or background tint) so the user can identify which message matched
- Other matches in the visible area are not highlighted -- only the current one

### Scroll Behavior

- On first search result: scroll to the most recent match (index 0, since results are timestamp DESC)
- On next/previous: scroll to that match with animation
- Uses existing `ScrollViewReader` and `.scrollTo(id, anchor: .center)`

## Changes

### TimelineViewModel

New state:

```swift
var isSearching: Bool = false
var searchQuery: String = ""
var searchResults: [String] = []      // event IDs from FTS
var currentSearchIndex: Int = 0
```

New methods:

```swift
func search() async                   // debounced, calls SearchProtocol
func nextResult()                     // increments index, wraps
func previousResult()                 // decrements index, wraps
func clearSearch()                    // resets all search state
```

New dependency: `searchService: (any SearchProtocol)?` -- passed from MainView, optional to avoid breaking existing init sites.

Debounce: 300ms after the user stops typing before executing the FTS query.

### TimelineView

- Conditionally render find bar above the ScrollView when `viewModel.isSearching`
- Pass `highlightedMessageID: viewModel.searchResults[safe: viewModel.currentSearchIndex]` to message rendering
- Scroll to `highlightedMessageID` when it changes
- Wire Cmd+F via `.onKeyPress` or toolbar button

### MessageBubbleView

- Accept optional `isHighlighted: Bool` parameter
- When true, apply a visual highlight (leading accent border or subtle background overlay)

### MainView

- Add Cmd+F keyboard shortcut that sets `timelineViewModel?.isSearching = true`

## Edge Cases

- **Empty query** -- clear results, hide match count
- **No matches** -- show "0 results" in the match count label
- **Room switch** -- `clearSearch()` when the selected room changes
- **Messages not loaded** -- if FTS returns an event ID that's not in the current `messages` array (because `messageLimit` is too low), call `loadMore()` until the message is visible, or skip to the next match that is visible
- **Query too short** -- FTS5 works with any length, but we can require 2+ characters to avoid noise

## Not In Scope

- Cross-room search (issue says "or in a specific one" -- that's a future enhancement)
- Search result snippets or previews
- Highlighting matched text within the message body (just the bubble highlight)
- Search history or recent searches
- Regex or advanced query syntax
