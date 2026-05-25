# Avatars, Read Status & Message Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the timeline, sidebar, and message bubbles with avatars, read receipts, send status, message grouping, and day separators.

**Architecture:** Add new model fields (avatarURL, sendStatus, readReceipts) and populate from SDK. Create a reusable AvatarView with async image loading and initial-letter fallback. Rewrite MessageBubbleView with grouping context. Update TimelineView with day separators and grouping logic. Update sidebar with avatars and timestamps.

**Tech Stack:** Swift, SwiftUI, MatrixRustSDK, NSCache for image caching

**Design spec:** `docs/superpowers/specs/2026-05-25-avatars-readstatus-messages-design.md`

---

## File Map

```
Modified:
  NebCore/Sources/NebCore/Models/NebMessage.swift     — add avatarURL, sendStatus, readReceipts
  NebCore/Sources/NebCore/Models/NebRoom.swift         — add avatarURL
  NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift — populate new message fields
  NebCore/Sources/NebCore/Adapters/MatrixSyncAdapter.swift — populate room avatarURL
  Neb/Views/Timeline/MessageBubbleView.swift           — complete rewrite with grouping
  Neb/Views/Timeline/TimelineView.swift                — day separators, grouping, read receipts
  Neb/Views/Sidebar/RoomRowView.swift                  — avatars, timestamps, preview format

New:
  NebCore/Sources/NebCore/Services/AvatarImageCache.swift — NSCache image loader
  NebCore/Sources/NebCore/Models/UserColorGenerator.swift — deterministic color from user ID
  Neb/Views/Common/AvatarView.swift                    — reusable avatar component
  Neb/Views/Timeline/DaySeparatorView.swift            — day separator pill
  Neb/Views/Timeline/ReadReceiptsView.swift            — tiny avatar row for read receipts
```

---

## Task 1: Data Model Updates

**Files:**
- Modify: `NebCore/Sources/NebCore/Models/NebMessage.swift`
- Modify: `NebCore/Sources/NebCore/Models/NebRoom.swift`

- [ ] **Step 1: Add new types and fields to NebMessage**

Replace `NebCore/Sources/NebCore/Models/NebMessage.swift` with:

```swift
import Foundation

public enum SendStatus: Equatable, Sendable {
    case sending
    case sent
    case failed
}

public struct ReadReceipt: Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let avatarURL: String?

    public init(userID: String, displayName: String, avatarURL: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public struct NebMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let roomID: String
    public let senderID: String
    public var senderDisplayName: String
    public var senderAvatarURL: String?
    public var body: String
    public var timestamp: Date
    public var isOutgoing: Bool
    public var sendStatus: SendStatus
    public var readReceipts: [ReadReceipt]

    public init(
        id: String,
        roomID: String,
        senderID: String,
        senderDisplayName: String,
        senderAvatarURL: String? = nil,
        body: String,
        timestamp: Date,
        isOutgoing: Bool,
        sendStatus: SendStatus = .sent,
        readReceipts: [ReadReceipt] = []
    ) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.senderAvatarURL = senderAvatarURL
        self.body = body
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.sendStatus = sendStatus
        self.readReceipts = readReceipts
    }
}
```

- [ ] **Step 2: Add avatarURL to NebRoom**

In `NebCore/Sources/NebCore/Models/NebRoom.swift`, add `avatarURL` field:

```swift
import Foundation

public struct NebRoom: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var avatarURL: String?
    public var lastMessage: String?
    public var lastMessageTimestamp: Date?
    public var unreadCount: UInt
    public var isDirect: Bool
    public var directUserID: String?
    public var memberCount: UInt

    public init(
        id: String,
        name: String,
        avatarURL: String? = nil,
        lastMessage: String? = nil,
        lastMessageTimestamp: Date? = nil,
        unreadCount: UInt = 0,
        isDirect: Bool = false,
        directUserID: String? = nil,
        memberCount: UInt = 0
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.isDirect = isDirect
        self.directUserID = directUserID
        self.memberCount = memberCount
    }
}
```

- [ ] **Step 3: Build and fix any compilation errors**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

The `NebMessage` init signature changed (new fields with defaults). Existing call sites in `MatrixRoomAdapter`'s `convertItem` should still compile since the new fields have defaults. Fix any errors.

- [ ] **Step 4: Commit**

```bash
git add NebCore/Sources/NebCore/Models/
git commit -m "feat: add avatar, send status, and read receipt fields to data models"
```

---

## Task 2: User Color Generator

**Files:**
- Create: `NebCore/Sources/NebCore/Models/UserColorGenerator.swift`

- [ ] **Step 1: Create UserColorGenerator**

Create `NebCore/Sources/NebCore/Models/UserColorGenerator.swift`:

```swift
import Foundation
import SwiftUI

public enum UserColorGenerator {
    private static let palette: [Color] = [
        Color(red: 0.48, green: 0.38, blue: 1.0),   // purple
        Color(red: 0.88, green: 0.48, blue: 0.29),   // orange
        Color(red: 0.30, green: 0.69, blue: 0.31),   // green
        Color(red: 0.90, green: 0.30, blue: 0.40),   // red-pink
        Color(red: 0.20, green: 0.60, blue: 0.86),   // blue
        Color(red: 0.85, green: 0.65, blue: 0.13),   // gold
        Color(red: 0.61, green: 0.35, blue: 0.71),   // violet
        Color(red: 0.00, green: 0.74, blue: 0.65),   // teal
        Color(red: 0.91, green: 0.38, blue: 0.65),   // magenta
        Color(red: 0.40, green: 0.73, blue: 0.42),   // lime-green
    ]

    public static func color(for userID: String) -> Color {
        var hash: UInt64 = 5381
        for byte in userID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Models/UserColorGenerator.swift
git commit -m "feat: deterministic user color generator from Matrix ID hash"
```

---

## Task 3: Avatar Image Cache

**Files:**
- Create: `NebCore/Sources/NebCore/Services/AvatarImageCache.swift`

- [ ] **Step 1: Create AvatarImageCache**

Create `NebCore/Sources/NebCore/Services/AvatarImageCache.swift`:

```swift
import Foundation
#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

public final class AvatarImageCache: @unchecked Sendable {
    public static let shared = AvatarImageCache()

    private let cache = NSCache<NSString, PlatformImage>()
    private var inflight: [String: Task<PlatformImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        cache.countLimit = 200
    }

    public func image(for mxcURL: String, homeserverURL: String) async -> PlatformImage? {
        if let cached = cache.object(forKey: mxcURL as NSString) {
            return cached
        }

        lock.lock()
        if let existing = inflight[mxcURL] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let httpURL = self.thumbnailURL(mxc: mxcURL, homeserver: homeserverURL) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: httpURL)
                guard let image = PlatformImage(data: data) else { return nil }
                self.cache.setObject(image, forKey: mxcURL as NSString)
                return image
            } catch {
                return nil
            }
        }
        inflight[mxcURL] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        inflight.removeValue(forKey: mxcURL)
        lock.unlock()

        return result
    }

    private func thumbnailURL(mxc: String, homeserver: String) -> URL? {
        // mxc://server.name/mediaId → https://homeserver/_matrix/media/v3/thumbnail/server.name/mediaId
        guard mxc.hasPrefix("mxc://") else { return nil }
        let path = String(mxc.dropFirst(6)) // "server.name/mediaId"
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        return URL(string: "\(base)/_matrix/media/v3/thumbnail/\(path)?width=64&height=64&method=crop")
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Services/AvatarImageCache.swift
git commit -m "feat: NSCache-based avatar image loader with mxc:// URL conversion"
```

---

## Task 4: AvatarView Component

**Files:**
- Create: `Neb/Views/Common/AvatarView.swift`

- [ ] **Step 1: Create AvatarView**

Create `Neb/Views/Common/AvatarView.swift`:

```swift
import SwiftUI
import NebCore

struct AvatarView: View {
    let size: CGFloat
    let name: String
    let userID: String
    var avatarURL: String?
    var homeserverURL: String = ""

    @State private var loadedImage: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(UserColorGenerator.color(for: userID))
                .frame(width: size, height: size)

            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)

            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .task(id: avatarURL) {
            guard let url = avatarURL, !url.isEmpty, !homeserverURL.isEmpty else { return }
            if let image = await AvatarImageCache.shared.image(for: url, homeserverURL: homeserverURL) {
                withAnimation(.easeIn(duration: 0.15)) {
                    loadedImage = image
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build with xcodegen**

```bash
cd /Users/mattog/dev/matto/neb
xcodegen generate
xcodebuild -project Neb.xcodeproj -scheme Neb -destination 'platform=macOS' build 2>&1 | tail -5
```

If `xcodebuild` is not available, just verify `swift build` in NebCore passes (AvatarView is in the app target, not NebCore).

- [ ] **Step 3: Commit**

```bash
git add Neb/Views/Common/AvatarView.swift
git commit -m "feat: reusable AvatarView with async image loading and initial fallback"
```

---

## Task 5: Populate Avatar and Send Status in Room Adapter

**Files:**
- Modify: `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift`

- [ ] **Step 1: Update convertItem to populate new fields**

In `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift`, update the `convertItem` method in `NebTimelineListener`. Replace the current `convertItem` method with:

```swift
    private func convertItem(_ item: TimelineItem) -> NebMessage? {
        guard let event = item.asEvent() else { return nil }
        guard case .msgLike(let msgLike) = event.content else { return nil }

        let body: String
        switch msgLike.kind {
        case .message(let msgContent):
            body = msgContent.body
        case .unableToDecrypt:
            body = "\u{1F512} Encrypted message (verify this device to decrypt)"
        default:
            return nil
        }

        let eventID: String
        switch event.eventOrTransactionId {
        case .eventId(let id):
            eventID = id
        case .transactionId(let id):
            eventID = id
        }

        var senderName = event.sender
        var senderAvatarURL: String? = nil
        switch event.senderProfile {
        case .ready(let displayName, let isNameAmbiguous, let avatarUrl):
            if let name = displayName { senderName = name }
            senderAvatarURL = avatarUrl
        default:
            break
        }

        let sendStatus: SendStatus
        if let localState = event.localSendState {
            switch localState {
            case .notSentYet:
                sendStatus = .sending
            case .sendingFailed:
                sendStatus = .failed
            case .sent:
                sendStatus = .sent
            }
        } else {
            sendStatus = .sent
        }

        let readReceipts: [ReadReceipt] = event.readReceipts
            .filter { $0.key != myUserID }
            .map { (userID, _) in
                ReadReceipt(userID: userID, displayName: userID)
            }

        return NebMessage(
            id: eventID,
            roomID: roomID,
            senderID: event.sender,
            senderDisplayName: senderName,
            senderAvatarURL: senderAvatarURL,
            body: body,
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1000),
            isOutgoing: event.isOwn,
            sendStatus: sendStatus,
            readReceipts: readReceipts
        )
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

The `EventSendState` cases may have associated values. If `.notSentYet(progress:)` or `.sendingFailed(error:, isRecoverable:)` don't match with the simplified patterns, update to: `case .notSentYet(_):` and `case .sendingFailed(_, _):`.

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift
git commit -m "feat: populate avatar URL, send status, and read receipts from SDK"
```

---

## Task 6: Populate Room Avatar URL in Sync Adapter

**Files:**
- Modify: `NebCore/Sources/NebCore/Adapters/MatrixSyncAdapter.swift`

- [ ] **Step 1: Add avatarURL to room conversion**

In `MatrixSyncAdapter.swift`, in the `convertAndEmit()` method, update the room construction to include `avatarURL`. Find the section where `NebRoom` is constructed and update:

```swift
                var isDirect = false
                var unread: UInt64 = 0
                var directUserID: String? = nil
                var avatarURL: String? = nil
                do {
                    let info = try await room.roomInfo()
                    isDirect = info.isDirect
                    unread = info.numUnreadNotifications
                    avatarURL = info.avatarUrl

                    if isDirect {
                        let myUserID = try? self.clientProvider()?.userId()
                        let members = try await room.membersNoSync()
                        while let chunk = members.nextChunk(chunkSize: 10) {
                            for member in chunk {
                                if member.userId != myUserID && member.membership == .join {
                                    directUserID = member.userId
                                    if avatarURL == nil {
                                        avatarURL = member.avatarUrl
                                    }
                                    break
                                }
                            }
                            if directUserID != nil { break }
                        }
                    }
                } catch {
                    logger.warning("Failed to get room info for \(roomID): \(error.localizedDescription)")
                }

                nebRooms.append(NebRoom(
                    id: roomID,
                    name: name,
                    avatarURL: avatarURL,
                    lastMessage: nil,
                    lastMessageTimestamp: nil,
                    unreadCount: UInt(unread),
                    isDirect: isDirect,
                    directUserID: directUserID,
                    memberCount: 0
                ))
```

Note: For DMs without a room avatar, we fall back to the DM partner's avatar. `RoomInfo.avatarUrl` is the room's avatar; `RoomMember.avatarUrl` is the user's.

- [ ] **Step 2: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Adapters/MatrixSyncAdapter.swift
git commit -m "feat: populate room avatar URL from room info and DM partner profile"
```

---

## Task 7: Day Separator View

**Files:**
- Create: `Neb/Views/Timeline/DaySeparatorView.swift`

- [ ] **Step 1: Create DaySeparatorView**

Create `Neb/Views/Timeline/DaySeparatorView.swift`:

```swift
import SwiftUI

struct DaySeparatorView: View {
    let date: Date

    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Timeline/DaySeparatorView.swift
git commit -m "feat: day separator pill view with relative date labels"
```

---

## Task 8: Read Receipts View

**Files:**
- Create: `Neb/Views/Timeline/ReadReceiptsView.swift`

- [ ] **Step 1: Create ReadReceiptsView**

Create `Neb/Views/Timeline/ReadReceiptsView.swift`:

```swift
import SwiftUI
import NebCore

struct ReadReceiptsView: View {
    let receipts: [ReadReceipt]
    let homeserverURL: String
    private let maxVisible = 3
    private let size: CGFloat = 14

    var body: some View {
        if !receipts.isEmpty {
            HStack(spacing: -4) {
                ForEach(Array(receipts.prefix(maxVisible).enumerated()), id: \.element.userID) { index, receipt in
                    AvatarView(
                        size: size,
                        name: receipt.displayName,
                        userID: receipt.userID,
                        avatarURL: receipt.avatarURL,
                        homeserverURL: homeserverURL
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.windowBackgroundColor), lineWidth: 1)
                    )
                    .zIndex(Double(maxVisible - index))
                }

                if receipts.count > maxVisible {
                    Text("+\(receipts.count - maxVisible)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Timeline/ReadReceiptsView.swift
git commit -m "feat: read receipt tiny avatar row with overflow count"
```

---

## Task 9: Message Bubble Rewrite

**Files:**
- Modify: `Neb/Views/Timeline/MessageBubbleView.swift`

- [ ] **Step 1: Rewrite MessageBubbleView**

Replace `Neb/Views/Timeline/MessageBubbleView.swift` entirely:

```swift
import SwiftUI
import NebCore

struct MessageBubbleView: View {
    let message: NebMessage
    let isFirstInGroup: Bool
    let isDM: Bool
    let homeserverURL: String

    private let avatarSize: CGFloat = 28
    private let avatarSpace: CGFloat = 36

    var body: some View {
        if message.isOutgoing {
            outgoingBubble
        } else {
            incomingBubble
        }
    }

    // MARK: - Outgoing

    private var outgoingBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Spacer(minLength: 60)
                bubbleContent
                    .background(Color.accentColor.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 12,
                            bottomLeading: 12,
                            bottomTrailing: isFirstInGroup ? 12 : 2,
                            topTrailing: isFirstInGroup ? 2 : 12
                        )
                    ))
            }

            if !message.readReceipts.isEmpty {
                ReadReceiptsView(receipts: message.readReceipts, homeserverURL: homeserverURL)
            } else if message.isOutgoing {
                sendStatusView
            }
        }
    }

    // MARK: - Incoming

    private var incomingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isDM {
                if isFirstInGroup {
                    AvatarView(
                        size: avatarSize,
                        name: message.senderDisplayName,
                        userID: message.senderID,
                        avatarURL: message.senderAvatarURL,
                        homeserverURL: homeserverURL
                    )
                } else {
                    Spacer().frame(width: avatarSize)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if isFirstInGroup && !isDM {
                    Text(message.senderDisplayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UserColorGenerator.color(for: message.senderID))
                }

                bubbleContent
                    .background(Color(.controlBackgroundColor))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(
                        cornerRadii: .init(
                            topLeading: isFirstInGroup ? 2 : 12,
                            bottomLeading: 12,
                            bottomTrailing: 12,
                            topTrailing: 12
                        )
                    ))
            }

            Spacer(minLength: 60)
        }
    }

    // MARK: - Bubble Content

    private var bubbleContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(message.body)
                .font(.system(size: 13))

            Text(message.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(message.isOutgoing ? .white.opacity(0.6) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Send Status

    @ViewBuilder
    private var sendStatusView: some View {
        switch message.sendStatus {
        case .sending:
            ProgressView()
                .controlSize(.mini)
        case .sent:
            Text("✓")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Timeline/MessageBubbleView.swift
git commit -m "feat: rewrite message bubble with grouping, avatars, inline timestamps, send status"
```

---

## Task 10: Timeline View with Grouping and Day Separators

**Files:**
- Modify: `Neb/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add homeserverURL to AppState and pass through**

The `AvatarView` and `ReadReceiptsView` need the homeserver URL to convert mxc:// to HTTP. Add it to `AppState`:

In `Neb/AppState.swift`, add a computed property:

```swift
    var homeserverURL: String {
        // Extract from the auth adapter's session, or use a default
        "https://matrix.matto.io"
    }
```

Note: This is hardcoded for now. A proper implementation would extract it from the stored session. For the PoC this is acceptable — it only affects avatar image loading.

Pass `homeserverURL` through `MainView` → `TimelineView`. Add `var homeserverURL: String = ""` to `MainView` and `TimelineView`.

In `NebApp.swift`, pass it:

```swift
MainView(
    roomListViewModel: roomListVM,
    roomServiceProvider: { appState.makeRoomService() },
    cryptoServiceProvider: { appState.makeCryptoService() },
    deviceVerificationStatus: appState.deviceVerificationStatus,
    homeserverURL: appState.homeserverURL,
    onLogout: { ... }
)
```

In `MainView`, pass to `TimelineView`:

```swift
TimelineView(
    viewModel: vm,
    roomName: room.name,
    isDM: room.isDirect,
    directUserID: room.directUserID,
    homeserverURL: homeserverURL,
    cryptoServiceProvider: cryptoServiceProvider
)
```

- [ ] **Step 2: Rewrite TimelineView with grouping and day separators**

Replace the body of `TimelineView` (keep the existing properties and toolbar/sheet logic):

Add a new property: `var isDM: Bool = false`

Replace the `ScrollView` content in the body:

```swift
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }

                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            let prev = index > 0 ? viewModel.messages[index - 1] : nil

                            if shouldShowDaySeparator(current: message, previous: prev) {
                                DaySeparatorView(date: message.timestamp)
                            }

                            MessageBubbleView(
                                message: message,
                                isFirstInGroup: isFirstInGroup(current: message, previous: prev),
                                isDM: isDM,
                                homeserverURL: homeserverURL
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, isFirstInGroup(current: message, previous: prev) ? 8 : 2)
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            MessageComposerView(viewModel: viewModel)
        }
        // ... keep existing .navigationTitle, .toolbar, .sheet, .task, .onChange
    }

    private func isFirstInGroup(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        if prev.senderID != current.senderID { return true }
        if current.timestamp.timeIntervalSince(prev.timestamp) > 300 { return true }
        if !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp) { return true }
        return false
    }

    private func shouldShowDaySeparator(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        return !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp)
    }
```

- [ ] **Step 3: Build and fix**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

Fix any compilation errors from the new parameters.

- [ ] **Step 4: Commit**

```bash
git add Neb/Views/Timeline/TimelineView.swift Neb/AppState.swift Neb/NebApp.swift Neb/Views/MainView.swift
git commit -m "feat: timeline with message grouping, day separators, and avatar support"
```

---

## Task 11: Sidebar Redesign

**Files:**
- Modify: `Neb/Views/Sidebar/RoomRowView.swift`

- [ ] **Step 1: Rewrite RoomRowView**

Replace `Neb/Views/Sidebar/RoomRowView.swift`:

```swift
import SwiftUI
import NebCore

struct RoomRowView: View {
    let room: NebRoom
    let homeserverURL: String

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(
                size: 32,
                name: room.name,
                userID: room.directUserID ?? room.id,
                avatarURL: room.avatarURL,
                homeserverURL: homeserverURL
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(room.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    if let ts = room.lastMessageTimestamp {
                        Text(relativeTimestamp(ts))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let lastMessage = room.lastMessage {
                    Text(lastMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if room.unreadCount > 0 {
                Text("\(room.unreadCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
```

- [ ] **Step 2: Update SidebarView to pass homeserverURL**

In `Neb/Views/Sidebar/SidebarView.swift`, add `var homeserverURL: String = ""` property and pass to `RoomRowView`:

```swift
RoomRowView(room: room, homeserverURL: homeserverURL)
```

Update `MainView` to pass `homeserverURL` to `SidebarView`:

```swift
SidebarView(
    viewModel: roomListViewModel,
    homeserverURL: homeserverURL,
    onNewDM: { showNewDM = true }
)
```

- [ ] **Step 3: Build and fix**

Fix any compilation errors from the changed `RoomRowView` initializer.

- [ ] **Step 4: Commit**

```bash
git add Neb/Views/Sidebar/RoomRowView.swift Neb/Views/Sidebar/SidebarView.swift Neb/Views/MainView.swift
git commit -m "feat: sidebar with avatars, relative timestamps, and improved room preview"
```

---

## Task 12: Integration Test

**Files:** None — manual verification.

- [ ] **Step 1: Build the full project**

```bash
cd /Users/mattog/dev/matto/neb
xcodegen generate
```

Build and run in Xcode.

- [ ] **Step 2: Verify sidebar**

- Rooms show avatar circles with initial letters (colored by user/room ID)
- DMs show the partner's initial/avatar
- Timestamps show relative format (time, "Yesterday", weekday, date)
- Unread badges still work

- [ ] **Step 3: Verify group chat timeline**

- First message in a sender group shows avatar + colored username
- Consecutive messages are compact (no avatar, no name)
- Timestamps inside bubbles
- Day separators between different days
- Grouping breaks after 5 minutes or different sender

- [ ] **Step 4: Verify DM timeline**

- No avatars or usernames on messages
- Same grouping and day separator logic
- Clean, compact layout

- [ ] **Step 5: Verify send status**

- Send a message — should show spinner then checkmark
- Checkmark disappears when read receipt appears

- [ ] **Step 6: Verify read receipts**

- Tiny avatar circles below messages where other users have read
- Multiple readers stack with overlap

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration adjustments for avatar and message redesign"
```
