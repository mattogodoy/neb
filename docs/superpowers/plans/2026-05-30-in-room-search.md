# In-Room Message Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cmd+F in-room message search with jump-between-matches navigation.

**Architecture:** TimelineViewModel gets search state and methods that call the existing `SearchProtocol`. TimelineView renders a find bar and highlights the current match. MessageBubbleView accepts an `isHighlighted` flag. MainView wires the Cmd+F shortcut. AppState exposes the existing `Room` adapter as a `SearchProtocol`.

**Tech Stack:** SwiftUI, NebCore (SearchProtocol, NebDatabase FTS5)

---

### Task 1: Add search service to AppState and MainView wiring

**Files:**
- Modify: `Neb/AppState.swift:118-123`
- Modify: `Neb/Views/MainView.swift:6-9,83-91`
- Modify: `Neb/NebApp.swift:27-31`

- [ ] **Step 1: Add makeSearchService() to AppState**

In `Neb/AppState.swift`, add after line 123 (`func makeSyncService()`):

```swift
func makeSearchService() -> any SearchProtocol { roomAdapter }
```

- [ ] **Step 2: Add searchServiceProvider to MainView**

In `Neb/Views/MainView.swift`, add a new property after line 9 (`var syncServiceProvider`):

```swift
var searchServiceProvider: (() -> any SearchProtocol)?
```

- [ ] **Step 3: Pass searchServiceProvider from NebApp**

In `Neb/NebApp.swift`, add after the `syncServiceProvider` line (line 31):

```swift
searchServiceProvider: { appState.makeSearchService() },
```

- [ ] **Step 4: Pass searchService when creating TimelineViewModel**

In `Neb/Views/MainView.swift`, update the `TimelineViewModel` init in `.onChange(of:)` (around line 83) to pass the search service:

```swift
timelineViewModel = TimelineViewModel(
    roomID: newID,
    roomService: timelineServiceProvider(),
    database: db,
    currentUserID: currentUserID ?? "",
    typingService: typingServiceProvider?(),
    syncService: syncServiceProvider?(),
    searchService: searchServiceProvider?(),
    initialUnreadCount: room?.unreadCount ?? 0
)
```

- [ ] **Step 5: Build to verify no errors**

Run: `cd NebCore && swift build`

This will fail until Task 2 adds the `searchService` parameter to TimelineViewModel. That's expected -- move to Task 2.

- [ ] **Step 6: Commit**

```bash
git add Neb/AppState.swift Neb/Views/MainView.swift Neb/NebApp.swift
git commit -m "feat: wire SearchProtocol through AppState and MainView"
```

---

### Task 2: Add search state and methods to TimelineViewModel

**Files:**
- Modify: `Neb/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add search properties**

In `TimelineViewModel`, after line 16 (`public var editingMessage`), add:

```swift
public var isSearching = false
public var searchQuery = ""
public private(set) var searchResultIDs: [String] = []
public private(set) var currentSearchIndex: Int = 0
```

- [ ] **Step 2: Add search service dependency and debounce task**

After line 24 (`private let syncService`), add:

```swift
private let searchService: (any SearchProtocol)?
```

After line 29 (`private var typingDebounceTask`), add:

```swift
@ObservationIgnored nonisolated(unsafe) private var searchDebounceTask: Task<Void, Never>?
```

- [ ] **Step 3: Update init to accept searchService**

Update the init signature (line 32) to add the parameter:

```swift
public init(
    roomID: String,
    roomService: any TimelineProtocol,
    database: NebDatabase,
    currentUserID: String,
    typingService: (any TypingProtocol)? = nil,
    syncService: (any SyncProtocol)? = nil,
    searchService: (any SearchProtocol)? = nil,
    initialUnreadCount: UInt = 0
) {
```

Add inside the init body, after `self.syncService = syncService`:

```swift
self.searchService = searchService
```

- [ ] **Step 4: Cancel search task in deinit**

In `deinit` (line 77), add:

```swift
searchDebounceTask?.cancel()
```

- [ ] **Step 5: Add search methods**

After the `submitEdit()` method (around line 162), add:

```swift
public func performSearch() {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    searchDebounceTask?.cancel()

    guard query.count >= 2 else {
        searchResultIDs = []
        currentSearchIndex = 0
        return
    }

    searchDebounceTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let self else { return }
        do {
            let results = try await self.searchService?.search(query: query, roomID: self.roomID) ?? []
            self.searchResultIDs = results.map(\.eventID)
            self.currentSearchIndex = 0
        } catch {
            logger.error("Search failed in \(self.roomID): \(error)")
            self.searchResultIDs = []
            self.currentSearchIndex = 0
        }
    }
}

public func nextSearchResult() {
    guard !searchResultIDs.isEmpty else { return }
    currentSearchIndex = (currentSearchIndex + 1) % searchResultIDs.count
}

public func previousSearchResult() {
    guard !searchResultIDs.isEmpty else { return }
    currentSearchIndex = (currentSearchIndex - 1 + searchResultIDs.count) % searchResultIDs.count
}

public func clearSearch() {
    isSearching = false
    searchQuery = ""
    searchResultIDs = []
    currentSearchIndex = 0
    searchDebounceTask?.cancel()
    searchDebounceTask = nil
}
```

- [ ] **Step 6: Add computed property for current highlighted ID**

After the search methods, add:

```swift
public var highlightedMessageID: String? {
    guard !searchResultIDs.isEmpty, searchResultIDs.indices.contains(currentSearchIndex) else { return nil }
    return searchResultIDs[currentSearchIndex]
}
```

- [ ] **Step 7: Build to verify**

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 8: Commit**

```bash
git add Neb/ViewModels/TimelineViewModel.swift
git commit -m "feat: add search state and methods to TimelineViewModel"
```

---

### Task 3: Add isHighlighted to MessageBubbleView

**Files:**
- Modify: `Neb/Views/Timeline/MessageBubbleView.swift`

- [ ] **Step 1: Add isHighlighted parameter**

In `MessageBubbleView`, after line 11 (`var onEdit`), add:

```swift
var isHighlighted: Bool = false
```

- [ ] **Step 2: Add highlight overlay to the body**

Wrap the existing `VStack` in the `body` property with an overlay. Replace lines 38-62 (the outer VStack) with:

```swift
VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 0) {
    if message.isOutgoing {
        outgoingBubble
    } else {
        incomingBubble
    }

    if !message.reactions.isEmpty {
        ReactionBarView(
            reactions: message.reactions,
            onToggle: { emoji in react(emoji) }
        )
        .font(.system(size: 12))
        .offset(y: -4)
        .padding(.leading, isDM ? 0 : avatarSize + 8)
    }

    if !message.readReceipts.isEmpty {
        HStack {
            Spacer()
            ReadReceiptsView(receipts: message.readReceipts, homeserverURL: homeserverURL)
        }
        .padding(.top, 4)
    }
}
.padding(.leading, isHighlighted ? 4 : 0)
.overlay(alignment: .leading) {
    if isHighlighted {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: 3)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add Neb/Views/Timeline/MessageBubbleView.swift
git commit -m "feat: add isHighlighted visual indicator to MessageBubbleView"
```

---

### Task 4: Add FindBarView

**Files:**
- Create: `Neb/Views/Timeline/FindBarView.swift`

- [ ] **Step 1: Create FindBarView**

Create `Neb/Views/Timeline/FindBarView.swift`:

```swift
import SwiftUI
import NebCore

struct FindBarView: View {
    @Bindable var viewModel: TimelineViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField("Search messages", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { viewModel.nextSearchResult() }
                .onChange(of: viewModel.searchQuery) {
                    viewModel.performSearch()
                }

            if !viewModel.searchQuery.isEmpty {
                matchCountLabel
            }

            Button(action: { viewModel.previousSearchResult() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchResultIDs.isEmpty)
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: { viewModel.nextSearchResult() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchResultIDs.isEmpty)
            .keyboardShortcut("g", modifiers: .command)

            Button(action: { viewModel.clearSearch() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var matchCountLabel: some View {
        if viewModel.searchResultIDs.isEmpty {
            Text("No results")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text("\(viewModel.currentSearchIndex + 1) of \(viewModel.searchResultIDs.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Run xcodegen**

Run: `xcodegen generate`

New file needs to be picked up by the Xcode project.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add -f Neb/Views/Timeline/FindBarView.swift
git commit -m "feat: add FindBarView for in-room message search"
```

---

### Task 5: Wire FindBarView into TimelineView with scroll-to-match

**Files:**
- Modify: `Neb/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add FindBarView above ScrollView**

In `TimelineView.swift`, replace the outer `VStack(spacing: 0)` body (lines 23-88) with:

```swift
VStack(spacing: 0) {
    if viewModel.isSearching {
        FindBarView(viewModel: viewModel)
        Divider()
    }

    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }

                ForEach(viewModel.messages) { message in
                    let layout = viewModel.messageLayouts[message.id]

                    if message.id == firstUnreadMessageID {
                        newMessagesSeparator
                            .id(ScrollTarget.newSeparator)
                    }

                    if layout?.showDaySeparator ?? true {
                        DaySeparatorView(date: message.timestamp)
                    }

                    MessageBubbleView(
                        message: message,
                        groupPosition: layout?.groupPosition ?? .alone,
                        isDM: isDM,
                        homeserverURL: homeserverURL,
                        onToggleReaction: { emoji in
                            Task { await viewModel.toggleReaction(eventID: message.id, emoji: emoji) }
                        },
                        onEdit: message.isEditable ? {
                            viewModel.editingMessage = message
                            viewModel.composerText = message.body
                        } : nil,
                        isHighlighted: message.id == viewModel.highlightedMessageID
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, (layout?.groupPosition == .first || layout?.groupPosition == .alone) ? 8 : 2)
                    .id(message.id)
                }

                if !viewModel.typingUsers.isEmpty {
                    TypingIndicatorView(users: viewModel.typingUsers)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .id("typing-indicator")
                }
            }
            .padding(.vertical, 8)

            Color.clear
                .frame(height: 1)
                .id(ScrollTarget.bottom)
        }
        .defaultScrollAnchor(.bottom)
        .task {
            await scrollToInitialPosition(with: proxy)
        }
        .onChange(of: viewModel.messages.last?.id) { oldID, newID in
            scrollAfterLiveMessageIfNeeded(from: oldID, to: newID, with: proxy)
        }
        .onChange(of: viewModel.highlightedMessageID) { _, newID in
            guard let newID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(newID, anchor: .center)
            }
        }
    }

    Divider()

    MessageComposerView(viewModel: viewModel)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Neb/Views/Timeline/TimelineView.swift
git commit -m "feat: wire FindBarView into TimelineView with scroll-to-match"
```

---

### Task 6: Add Cmd+F keyboard shortcut

**Files:**
- Modify: `Neb/NebApp.swift:67-73`

- [ ] **Step 1: Add Find command to NebApp**

In `Neb/NebApp.swift`, add a new `CommandGroup` inside `.commands` (after the existing `CommandGroup(replacing: .newItem)` block, around line 73):

```swift
CommandGroup(after: .textEditing) {
    Button("Find in Conversation") {
        NotificationCenter.default.post(name: .toggleFindBar, object: nil)
    }
    .keyboardShortcut("f", modifiers: .command)
}
```

- [ ] **Step 2: Add Notification.Name extension**

At the bottom of `Neb/NebApp.swift`, outside the struct, add:

```swift
extension Notification.Name {
    static let toggleFindBar = Notification.Name("toggleFindBar")
}
```

- [ ] **Step 3: Listen for the notification in MainView**

In `Neb/Views/MainView.swift`, add a modifier after `.sheet(isPresented: $showDeviceVerification)` (around line 114):

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleFindBar)) { _ in
    if timelineViewModel != nil {
        if timelineViewModel?.isSearching == true {
            timelineViewModel?.clearSearch()
        } else {
            timelineViewModel?.isSearching = true
        }
    }
}
```

Add `import Combine` at the top of MainView.swift if not already there.

- [ ] **Step 4: Clear search on room switch**

In `Neb/Views/MainView.swift`, in the `.onChange(of: roomListViewModel.selectedRoom?.id)` handler, add `timelineViewModel?.clearSearch()` before creating the new view model:

```swift
.onChange(of: roomListViewModel.selectedRoom?.id) { _, newID in
    timelineViewModel?.clearSearch()
    if let newID, let db = database {
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add Neb/NebApp.swift Neb/Views/MainView.swift
git commit -m "feat: add Cmd+F keyboard shortcut for in-room search"
```

---

### Task 7: Final build and manual test

- [ ] **Step 1: Full build**

```bash
xcodegen generate
xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 2: Run tests**

```bash
cd NebCore && swift test
```

All existing tests should pass -- no NebCore changes were made.

- [ ] **Step 3: Commit plan**

```bash
git add -f docs/superpowers/plans/2026-05-30-in-room-search.md
git commit -m "docs: in-room search implementation plan"
```
