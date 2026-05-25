# Emoji Reactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add emoji reactions to messages — view existing reactions, add/remove reactions via hover→quick bar→full picker flow.

**Architecture:** Add NebReaction model and reactions field to NebMessage. Populate from SDK's MsgLikeContent.reactions in the timeline adapter. Add toggleReaction to RoomServiceProtocol. Build three UI layers: ReactionBarView (display), QuickReactBar (quick add), EmojiPickerView (full picker). Wire into MessageBubbleView with hover state.

**Tech Stack:** Swift, SwiftUI, MatrixRustSDK, UserDefaults for recent emoji

**Design spec:** `docs/superpowers/specs/2026-05-25-reactions-design.md`

---

## File Map

```
New:
  NebCore/Sources/NebCore/Models/NebReaction.swift      — reaction data model
  Neb/Views/Timeline/ReactionBarView.swift               — reaction pills below message
  Neb/Views/Timeline/QuickReactBar.swift                 — floating 6-emoji bar
  Neb/Views/Common/EmojiPickerView.swift                 — full emoji picker with search
  Neb/Views/Common/EmojiData.swift                       — hardcoded emoji arrays by category

Modified:
  NebCore/Sources/NebCore/Models/NebMessage.swift        — add reactions field
  NebCore/Sources/NebCore/Services/RoomServiceProtocol.swift — add toggleReaction
  NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift   — implement toggleReaction, populate reactions
  NebCore/Tests/NebCoreTests/Mocks/MockRoomService.swift     — add toggleReaction mock
  Neb/Views/Timeline/MessageBubbleView.swift             — hover smiley, reaction bar, popover triggers
```

---

## Task 1: Data Model & Protocol

**Files:**
- Create: `NebCore/Sources/NebCore/Models/NebReaction.swift`
- Modify: `NebCore/Sources/NebCore/Models/NebMessage.swift`
- Modify: `NebCore/Sources/NebCore/Services/RoomServiceProtocol.swift`
- Modify: `NebCore/Tests/NebCoreTests/Mocks/MockRoomService.swift`

- [ ] **Step 1: Create NebReaction**

Create `NebCore/Sources/NebCore/Models/NebReaction.swift`:

```swift
import Foundation

public struct NebReaction: Equatable, Sendable {
    public let emoji: String
    public let count: Int
    public let senderIDs: [String]
    public let includesMe: Bool

    public init(emoji: String, count: Int, senderIDs: [String], includesMe: Bool) {
        self.emoji = emoji
        self.count = count
        self.senderIDs = senderIDs
        self.includesMe = includesMe
    }
}
```

- [ ] **Step 2: Add reactions to NebMessage**

In `NebCore/Sources/NebCore/Models/NebMessage.swift`, add `reactions` field after `readReceipts`:

```swift
public var reactions: [NebReaction]
```

And add it to the init with a default:

```swift
    public init(
        ...
        readReceipts: [ReadReceipt] = [],
        reactions: [NebReaction] = []
    ) {
        ...
        self.readReceipts = readReceipts
        self.reactions = reactions
    }
```

- [ ] **Step 3: Add toggleReaction to RoomServiceProtocol**

In `NebCore/Sources/NebCore/Services/RoomServiceProtocol.swift`, add:

```swift
func toggleReaction(roomID: String, eventID: String, emoji: String) async throws
```

- [ ] **Step 4: Add toggleReaction to MockRoomService**

In `NebCore/Tests/NebCoreTests/Mocks/MockRoomService.swift`, add:

```swift
var toggledReactions: [(roomID: String, eventID: String, emoji: String)] = []

func toggleReaction(roomID: String, eventID: String, emoji: String) async throws {
    toggledReactions.append((roomID: roomID, eventID: eventID, emoji: emoji))
}
```

- [ ] **Step 5: Build and test**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build && swift test
```

- [ ] **Step 6: Commit**

```bash
git add NebCore/Sources/NebCore/Models/NebReaction.swift \
       NebCore/Sources/NebCore/Models/NebMessage.swift \
       NebCore/Sources/NebCore/Services/RoomServiceProtocol.swift \
       NebCore/Tests/NebCoreTests/Mocks/MockRoomService.swift
git commit -m "feat: add NebReaction model and toggleReaction to service protocol"
```

---

## Task 2: Populate Reactions in Adapter & Implement toggleReaction

**Files:**
- Modify: `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift`

- [ ] **Step 1: Populate reactions in convertItem**

In `NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift`, in the `convertItem` method of `NebTimelineListener`, add reaction mapping after the `readReceipts` construction and before the `return NebMessage(...)`:

```swift
        let reactions: [NebReaction] = msgLike.reactions.map { reaction in
            NebReaction(
                emoji: reaction.key,
                count: reaction.senders.count,
                senderIDs: reaction.senders.map(\.senderId),
                includesMe: reaction.senders.contains { $0.senderId == myUserID }
            )
        }
```

Then add `reactions: reactions` to the NebMessage constructor call.

- [ ] **Step 2: Implement toggleReaction on MatrixRoomAdapter**

In the `MatrixRoomAdapter` class (not the listener), add the method. Read the current file to find where to add it (after `paginateBackwards`):

```swift
    public func toggleReaction(roomID: String, eventID: String, emoji: String) async throws {
        guard let handle = activeTimelines[roomID] else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        let _ = try await handle.timeline.toggleReaction(itemId: itemID, key: emoji)
    }
```

Note: `EventOrTransactionId` is from `MatrixRustSDK`. The `activeTimelines` dictionary holds `TimelineHandle` which has the `timeline` property.

- [ ] **Step 3: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

- [ ] **Step 4: Commit**

```bash
git add NebCore/Sources/NebCore/Adapters/MatrixRoomAdapter.swift
git commit -m "feat: populate reactions from SDK and implement toggleReaction"
```

---

## Task 3: Emoji Data

**Files:**
- Create: `Neb/Views/Common/EmojiData.swift`

- [ ] **Step 1: Create EmojiData with categories**

Create `Neb/Views/Common/EmojiData.swift`. This file contains hardcoded emoji arrays. Below is a representative subset — include the full standard set for each category:

```swift
import Foundation

struct EmojiCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let emojis: [EmojiItem]
}

struct EmojiItem: Identifiable {
    let id: String
    let emoji: String
    let keywords: [String]

    init(_ emoji: String, _ keywords: [String] = []) {
        self.id = emoji
        self.emoji = emoji
        self.keywords = keywords
    }
}

enum EmojiData {
    static let defaultQuickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    static let categories: [EmojiCategory] = [
        EmojiCategory(id: "recent", name: "Recent", icon: "clock", emojis: []),
        EmojiCategory(id: "smileys", name: "Smileys & People", icon: "face.smiling", emojis: smileys),
        EmojiCategory(id: "animals", name: "Animals & Nature", icon: "hare", emojis: animals),
        EmojiCategory(id: "food", name: "Food & Drink", icon: "fork.knife", emojis: food),
        EmojiCategory(id: "travel", name: "Travel & Places", icon: "car", emojis: travel),
        EmojiCategory(id: "activities", name: "Activities", icon: "sportscourt", emojis: activities),
        EmojiCategory(id: "objects", name: "Objects", icon: "lightbulb", emojis: objects),
        EmojiCategory(id: "symbols", name: "Symbols", icon: "heart", emojis: symbols),
        EmojiCategory(id: "flags", name: "Flags", icon: "flag", emojis: flags),
    ]

    static let smileys: [EmojiItem] = [
        EmojiItem("😀", ["grinning", "happy"]),
        EmojiItem("😃", ["smiley", "happy"]),
        EmojiItem("😄", ["smile", "happy"]),
        EmojiItem("😁", ["grin"]),
        EmojiItem("😆", ["laughing"]),
        EmojiItem("😅", ["sweat smile"]),
        EmojiItem("🤣", ["rofl", "laughing"]),
        EmojiItem("😂", ["joy", "tears"]),
        EmojiItem("🙂", ["slightly smiling"]),
        EmojiItem("🙃", ["upside down"]),
        EmojiItem("😉", ["wink"]),
        EmojiItem("😊", ["blush"]),
        EmojiItem("😇", ["innocent", "angel"]),
        EmojiItem("🥰", ["love", "hearts"]),
        EmojiItem("😍", ["heart eyes"]),
        EmojiItem("🤩", ["star struck"]),
        EmojiItem("😘", ["kiss"]),
        EmojiItem("😗", ["kissing"]),
        EmojiItem("😚", ["kissing closed"]),
        EmojiItem("😙", ["kissing smiling"]),
        EmojiItem("🥲", ["smiling tear"]),
        EmojiItem("😋", ["yum", "delicious"]),
        EmojiItem("😛", ["tongue"]),
        EmojiItem("😜", ["wink tongue"]),
        EmojiItem("🤪", ["zany", "crazy"]),
        EmojiItem("😝", ["tongue closed"]),
        EmojiItem("🤑", ["money"]),
        EmojiItem("🤗", ["hug"]),
        EmojiItem("🤭", ["hand over mouth"]),
        EmojiItem("🤫", ["shush", "quiet"]),
        EmojiItem("🤔", ["thinking", "hmm"]),
        EmojiItem("🫡", ["salute"]),
        EmojiItem("🤐", ["zipper mouth"]),
        EmojiItem("🤨", ["raised eyebrow"]),
        EmojiItem("😐", ["neutral"]),
        EmojiItem("😑", ["expressionless"]),
        EmojiItem("😶", ["no mouth"]),
        EmojiItem("🫥", ["dotted line"]),
        EmojiItem("😏", ["smirk"]),
        EmojiItem("😒", ["unamused"]),
        EmojiItem("🙄", ["eye roll"]),
        EmojiItem("😬", ["grimace"]),
        EmojiItem("🤥", ["liar", "pinocchio"]),
        EmojiItem("😌", ["relieved"]),
        EmojiItem("😔", ["pensive"]),
        EmojiItem("😪", ["sleepy"]),
        EmojiItem("🤤", ["drool"]),
        EmojiItem("😴", ["sleeping", "zzz"]),
        EmojiItem("😷", ["mask", "sick"]),
        EmojiItem("🤒", ["thermometer", "sick"]),
        EmojiItem("🤕", ["bandage", "hurt"]),
        EmojiItem("🤢", ["nausea", "sick"]),
        EmojiItem("🤮", ["vomit"]),
        EmojiItem("🥵", ["hot"]),
        EmojiItem("🥶", ["cold", "freezing"]),
        EmojiItem("😵", ["dizzy"]),
        EmojiItem("🤯", ["mind blown", "exploding"]),
        EmojiItem("🥳", ["party", "celebration"]),
        EmojiItem("🥸", ["disguise"]),
        EmojiItem("😎", ["cool", "sunglasses"]),
        EmojiItem("🤓", ["nerd"]),
        EmojiItem("🧐", ["monocle"]),
        EmojiItem("😕", ["confused"]),
        EmojiItem("😟", ["worried"]),
        EmojiItem("🙁", ["frown"]),
        EmojiItem("😮", ["open mouth", "surprised"]),
        EmojiItem("😯", ["hushed"]),
        EmojiItem("😲", ["astonished"]),
        EmojiItem("😳", ["flushed"]),
        EmojiItem("🥺", ["pleading", "puppy eyes"]),
        EmojiItem("😦", ["frowning mouth"]),
        EmojiItem("😧", ["anguished"]),
        EmojiItem("😨", ["fearful"]),
        EmojiItem("😰", ["anxious sweat"]),
        EmojiItem("😥", ["disappointed relieved"]),
        EmojiItem("😢", ["cry"]),
        EmojiItem("😭", ["sob", "crying"]),
        EmojiItem("😱", ["scream"]),
        EmojiItem("😖", ["confounded"]),
        EmojiItem("😣", ["persevere"]),
        EmojiItem("😞", ["disappointed"]),
        EmojiItem("😓", ["downcast sweat"]),
        EmojiItem("😩", ["weary"]),
        EmojiItem("😫", ["tired"]),
        EmojiItem("🥱", ["yawn"]),
        EmojiItem("😤", ["triumph", "angry"]),
        EmojiItem("😡", ["rage", "angry"]),
        EmojiItem("😠", ["angry"]),
        EmojiItem("🤬", ["cursing"]),
        EmojiItem("😈", ["devil"]),
        EmojiItem("👿", ["imp"]),
        EmojiItem("💀", ["skull", "dead"]),
        EmojiItem("☠️", ["skull crossbones"]),
        EmojiItem("💩", ["poop"]),
        EmojiItem("🤡", ["clown"]),
        EmojiItem("👹", ["ogre"]),
        EmojiItem("👻", ["ghost"]),
        EmojiItem("👽", ["alien"]),
        EmojiItem("🤖", ["robot"]),
        EmojiItem("😺", ["cat smile"]),
        EmojiItem("😸", ["cat grin"]),
        EmojiItem("😹", ["cat joy"]),
        EmojiItem("😻", ["cat heart eyes"]),
        EmojiItem("🙈", ["see no evil"]),
        EmojiItem("🙉", ["hear no evil"]),
        EmojiItem("🙊", ["speak no evil"]),
        EmojiItem("👋", ["wave", "hello"]),
        EmojiItem("🤚", ["raised back"]),
        EmojiItem("✋", ["hand", "high five"]),
        EmojiItem("🖖", ["vulcan"]),
        EmojiItem("👌", ["ok"]),
        EmojiItem("🤌", ["pinched fingers"]),
        EmojiItem("🤏", ["pinching"]),
        EmojiItem("✌️", ["peace", "victory"]),
        EmojiItem("🤞", ["crossed fingers"]),
        EmojiItem("🫰", ["hand with index finger and thumb crossed"]),
        EmojiItem("🤟", ["love you"]),
        EmojiItem("🤘", ["rock", "metal"]),
        EmojiItem("🤙", ["call me"]),
        EmojiItem("👈", ["point left"]),
        EmojiItem("👉", ["point right"]),
        EmojiItem("👆", ["point up"]),
        EmojiItem("🖕", ["middle finger"]),
        EmojiItem("👇", ["point down"]),
        EmojiItem("☝️", ["point up one"]),
        EmojiItem("👍", ["thumbs up", "like"]),
        EmojiItem("👎", ["thumbs down", "dislike"]),
        EmojiItem("✊", ["fist"]),
        EmojiItem("👊", ["punch"]),
        EmojiItem("🤛", ["left fist"]),
        EmojiItem("🤜", ["right fist"]),
        EmojiItem("👏", ["clap"]),
        EmojiItem("🙌", ["raised hands", "hooray"]),
        EmojiItem("🫶", ["heart hands"]),
        EmojiItem("👐", ["open hands"]),
        EmojiItem("🤲", ["palms up"]),
        EmojiItem("🤝", ["handshake"]),
        EmojiItem("🙏", ["pray", "please", "thanks"]),
        EmojiItem("💪", ["muscle", "strong"]),
        EmojiItem("❤️", ["red heart", "love"]),
        EmojiItem("🔥", ["fire", "hot"]),
        EmojiItem("💯", ["hundred", "perfect"]),
        EmojiItem("⭐", ["star"]),
        EmojiItem("🎉", ["party", "tada"]),
        EmojiItem("✅", ["check", "done"]),
        EmojiItem("❌", ["cross", "no"]),
        EmojiItem("⚠️", ["warning"]),
        EmojiItem("💡", ["idea", "bulb"]),
        EmojiItem("👀", ["eyes", "look"]),
        EmojiItem("🎵", ["music", "note"]),
    ]

    // Provide smaller representative sets for other categories.
    // The engineer should expand these with full Unicode emoji sets.

    static let animals: [EmojiItem] = [
        EmojiItem("🐶", ["dog"]), EmojiItem("🐱", ["cat"]), EmojiItem("🐭", ["mouse"]),
        EmojiItem("🐹", ["hamster"]), EmojiItem("🐰", ["rabbit"]), EmojiItem("🦊", ["fox"]),
        EmojiItem("🐻", ["bear"]), EmojiItem("🐼", ["panda"]), EmojiItem("🐨", ["koala"]),
        EmojiItem("🐯", ["tiger"]), EmojiItem("🦁", ["lion"]), EmojiItem("🐮", ["cow"]),
        EmojiItem("🐷", ["pig"]), EmojiItem("🐸", ["frog"]), EmojiItem("🐵", ["monkey"]),
        EmojiItem("🐔", ["chicken"]), EmojiItem("🐧", ["penguin"]), EmojiItem("🐦", ["bird"]),
        EmojiItem("🦅", ["eagle"]), EmojiItem("🦉", ["owl"]), EmojiItem("🐺", ["wolf"]),
        EmojiItem("🐗", ["boar"]), EmojiItem("🐴", ["horse"]), EmojiItem("🦄", ["unicorn"]),
        EmojiItem("🐝", ["bee"]), EmojiItem("🐛", ["bug"]), EmojiItem("🦋", ["butterfly"]),
        EmojiItem("🐌", ["snail"]), EmojiItem("🐞", ["ladybug"]), EmojiItem("🐙", ["octopus"]),
        EmojiItem("🦈", ["shark"]), EmojiItem("🐬", ["dolphin"]), EmojiItem("🐳", ["whale"]),
        EmojiItem("🌸", ["cherry blossom"]), EmojiItem("🌹", ["rose"]), EmojiItem("🌻", ["sunflower"]),
        EmojiItem("🌲", ["tree"]), EmojiItem("🌵", ["cactus"]), EmojiItem("🍀", ["clover", "lucky"]),
    ]

    static let food: [EmojiItem] = [
        EmojiItem("🍎", ["apple"]), EmojiItem("🍐", ["pear"]), EmojiItem("🍊", ["orange"]),
        EmojiItem("🍋", ["lemon"]), EmojiItem("🍌", ["banana"]), EmojiItem("🍉", ["watermelon"]),
        EmojiItem("🍇", ["grapes"]), EmojiItem("🍓", ["strawberry"]), EmojiItem("🫐", ["blueberry"]),
        EmojiItem("🍑", ["peach"]), EmojiItem("🥝", ["kiwi"]), EmojiItem("🍒", ["cherry"]),
        EmojiItem("🥑", ["avocado"]), EmojiItem("🍕", ["pizza"]), EmojiItem("🍔", ["burger"]),
        EmojiItem("🌮", ["taco"]), EmojiItem("🍟", ["fries"]), EmojiItem("🍿", ["popcorn"]),
        EmojiItem("🍩", ["donut"]), EmojiItem("🍪", ["cookie"]), EmojiItem("🎂", ["cake", "birthday"]),
        EmojiItem("🍫", ["chocolate"]), EmojiItem("☕", ["coffee"]), EmojiItem("🍺", ["beer"]),
        EmojiItem("🍷", ["wine"]), EmojiItem("🥤", ["drink"]), EmojiItem("🧋", ["boba", "bubble tea"]),
    ]

    static let travel: [EmojiItem] = [
        EmojiItem("🚗", ["car"]), EmojiItem("🚕", ["taxi"]), EmojiItem("🚌", ["bus"]),
        EmojiItem("🚎", ["trolleybus"]), EmojiItem("🏎️", ["race car"]), EmojiItem("🚓", ["police car"]),
        EmojiItem("✈️", ["airplane"]), EmojiItem("🚀", ["rocket"]), EmojiItem("🛸", ["ufo"]),
        EmojiItem("🚁", ["helicopter"]), EmojiItem("⛵", ["sailboat"]), EmojiItem("🚂", ["train"]),
        EmojiItem("🏠", ["house"]), EmojiItem("🏢", ["office"]), EmojiItem("🏖️", ["beach"]),
        EmojiItem("⛰️", ["mountain"]), EmojiItem("🌍", ["earth", "world"]), EmojiItem("🌙", ["moon"]),
        EmojiItem("☀️", ["sun"]), EmojiItem("⭐", ["star"]), EmojiItem("🌈", ["rainbow"]),
    ]

    static let activities: [EmojiItem] = [
        EmojiItem("⚽", ["soccer"]), EmojiItem("🏀", ["basketball"]), EmojiItem("🏈", ["football"]),
        EmojiItem("⚾", ["baseball"]), EmojiItem("🎾", ["tennis"]), EmojiItem("🏐", ["volleyball"]),
        EmojiItem("🎮", ["gaming", "controller"]), EmojiItem("🎲", ["dice", "game"]),
        EmojiItem("🎯", ["target", "bullseye"]), EmojiItem("🎳", ["bowling"]),
        EmojiItem("🏆", ["trophy", "winner"]), EmojiItem("🥇", ["gold medal", "first"]),
        EmojiItem("🎪", ["circus"]), EmojiItem("🎨", ["art", "palette"]),
        EmojiItem("🎬", ["movie", "film"]), EmojiItem("🎤", ["microphone", "singing"]),
        EmojiItem("🎧", ["headphones"]), EmojiItem("🎸", ["guitar"]),
    ]

    static let objects: [EmojiItem] = [
        EmojiItem("💻", ["laptop", "computer"]), EmojiItem("📱", ["phone", "mobile"]),
        EmojiItem("⌨️", ["keyboard"]), EmojiItem("🖥️", ["desktop", "monitor"]),
        EmojiItem("📷", ["camera"]), EmojiItem("📸", ["camera flash"]),
        EmojiItem("💡", ["light bulb", "idea"]), EmojiItem("🔦", ["flashlight"]),
        EmojiItem("📚", ["books"]), EmojiItem("📖", ["book", "open"]),
        EmojiItem("✏️", ["pencil"]), EmojiItem("🖊️", ["pen"]),
        EmojiItem("📎", ["paperclip"]), EmojiItem("🔑", ["key"]),
        EmojiItem("🔒", ["lock"]), EmojiItem("🔓", ["unlock"]),
        EmojiItem("🛠️", ["tools"]), EmojiItem("⚙️", ["gear", "settings"]),
    ]

    static let symbols: [EmojiItem] = [
        EmojiItem("❤️", ["red heart"]), EmojiItem("🧡", ["orange heart"]),
        EmojiItem("💛", ["yellow heart"]), EmojiItem("💚", ["green heart"]),
        EmojiItem("💙", ["blue heart"]), EmojiItem("💜", ["purple heart"]),
        EmojiItem("🖤", ["black heart"]), EmojiItem("🤍", ["white heart"]),
        EmojiItem("💔", ["broken heart"]), EmojiItem("❣️", ["heart exclamation"]),
        EmojiItem("💕", ["two hearts"]), EmojiItem("💞", ["revolving hearts"]),
        EmojiItem("💓", ["heartbeat"]), EmojiItem("💗", ["growing heart"]),
        EmojiItem("✅", ["check mark"]), EmojiItem("❌", ["cross mark"]),
        EmojiItem("❓", ["question"]), EmojiItem("❗", ["exclamation"]),
        EmojiItem("⚠️", ["warning"]), EmojiItem("♻️", ["recycle"]),
        EmojiItem("💤", ["zzz", "sleep"]), EmojiItem("💬", ["speech bubble"]),
        EmojiItem("👁️‍🗨️", ["eye in speech"]), EmojiItem("🔔", ["bell"]),
    ]

    static let flags: [EmojiItem] = [
        EmojiItem("🏁", ["checkered flag"]), EmojiItem("🚩", ["red flag"]),
        EmojiItem("🏳️", ["white flag"]), EmojiItem("🏴", ["black flag"]),
        EmojiItem("🏳️‍🌈", ["rainbow flag", "pride"]),
        EmojiItem("🇺🇸", ["us", "usa"]), EmojiItem("🇬🇧", ["uk", "gb"]),
        EmojiItem("🇪🇸", ["spain"]), EmojiItem("🇫🇷", ["france"]),
        EmojiItem("🇩🇪", ["germany"]), EmojiItem("🇮🇹", ["italy"]),
        EmojiItem("🇯🇵", ["japan"]), EmojiItem("🇰🇷", ["korea"]),
        EmojiItem("🇨🇳", ["china"]), EmojiItem("🇧🇷", ["brazil"]),
        EmojiItem("🇲🇽", ["mexico"]), EmojiItem("🇦🇷", ["argentina"]),
        EmojiItem("🇦🇺", ["australia"]), EmojiItem("🇨🇦", ["canada"]),
    ]

    static func search(_ query: String) -> [EmojiItem] {
        let q = query.lowercased()
        return categories.flatMap(\.emojis).filter { item in
            item.emoji.contains(q) || item.keywords.contains { $0.contains(q) }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Common/EmojiData.swift
git commit -m "feat: hardcoded emoji data with categories and keyword search"
```

---

## Task 4: Reaction Bar View

**Files:**
- Create: `Neb/Views/Timeline/ReactionBarView.swift`

- [ ] **Step 1: Create ReactionBarView**

Create `Neb/Views/Timeline/ReactionBarView.swift`:

```swift
import SwiftUI
import NebCore

struct ReactionBarView: View {
    let reactions: [NebReaction]
    let onToggle: (String) -> Void
    let onAddReaction: () -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(reactions, id: \.emoji) { reaction in
                Button(action: { onToggle(reaction.emoji) }) {
                    HStack(spacing: 3) {
                        Text(reaction.emoji)
                            .font(.system(size: 14))
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(reaction.includesMe ? .white : .secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(reaction.includesMe ? Color.accentColor.opacity(0.3) : Color(.controlBackgroundColor))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(
                            reaction.includesMe ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            Button(action: onAddReaction) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Timeline/ReactionBarView.swift
git commit -m "feat: reaction bar with pills, toggle, and flow layout"
```

---

## Task 5: Quick React Bar

**Files:**
- Create: `Neb/Views/Timeline/QuickReactBar.swift`

- [ ] **Step 1: Create QuickReactBar**

Create `Neb/Views/Timeline/QuickReactBar.swift`:

```swift
import SwiftUI

struct QuickReactBar: View {
    let onReact: (String) -> Void
    let onOpenPicker: () -> Void

    private var quickEmoji: [String] {
        let recent = RecentReactions.shared.list
        return Array(recent.prefix(6))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(quickEmoji, id: \.self) { emoji in
                Button(action: { onReact(emoji) }) {
                    Text(emoji)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }

            Button(action: onOpenPicker) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

class RecentReactions {
    static let shared = RecentReactions()
    private let key = "recentReactions"
    private let maxCount = 20

    var list: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? EmojiData.defaultQuickReactions
    }

    func recordReaction(_ emoji: String) {
        var recent = list
        recent.removeAll { $0 == emoji }
        recent.insert(emoji, at: 0)
        if recent.count > maxCount {
            recent = Array(recent.prefix(maxCount))
        }
        UserDefaults.standard.set(recent, forKey: key)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Timeline/QuickReactBar.swift
git commit -m "feat: quick react bar with recent emoji and UserDefaults persistence"
```

---

## Task 6: Full Emoji Picker

**Files:**
- Create: `Neb/Views/Common/EmojiPickerView.swift`

- [ ] **Step 1: Create EmojiPickerView**

Create `Neb/Views/Common/EmojiPickerView.swift`:

```swift
import SwiftUI

struct EmojiPickerView: View {
    let onSelect: (String) -> Void
    @State private var searchText = ""
    @State private var selectedCategory = "smileys"

    var body: some View {
        VStack(spacing: 0) {
            categoryTabs
            Divider()
            searchBar
            emojiGrid
        }
        .frame(width: 320, height: 360)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(EmojiData.categories) { category in
                    Button(action: {
                        selectedCategory = category.id
                        searchText = ""
                    }) {
                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(selectedCategory == category.id ? Color.accentColor : .secondary)
                            .background(selectedCategory == category.id ? Color.accentColor.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search emoji", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var emojiGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
                if !searchText.isEmpty {
                    let results = EmojiData.search(searchText)
                    ForEach(results) { item in
                        emojiButton(item.emoji)
                    }
                } else if selectedCategory == "recent" {
                    let recent = RecentReactions.shared.list
                    ForEach(recent, id: \.self) { emoji in
                        emojiButton(emoji)
                    }
                } else if let category = EmojiData.categories.first(where: { $0.id == selectedCategory }) {
                    ForEach(category.emojis) { item in
                        emojiButton(item.emoji)
                    }
                }
            }
            .padding(8)
        }
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button(action: { onSelect(emoji) }) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Neb/Views/Common/EmojiPickerView.swift
git commit -m "feat: full emoji picker with category tabs, search, and recent reactions"
```

---

## Task 7: Wire Reactions into MessageBubbleView

**Files:**
- Modify: `Neb/Views/Timeline/MessageBubbleView.swift`

- [ ] **Step 1: Add reaction state and callbacks to MessageBubbleView**

Read the current `MessageBubbleView.swift`. Add these properties and state:

```swift
    let onToggleReaction: (String) -> Void

    @State private var isHovered = false
    @State private var showQuickReact = false
    @State private var showEmojiPicker = false
```

- [ ] **Step 2: Add hover smiley overlay**

Wrap the existing body content. After the read receipts `HStack`, before the closing of the outer `VStack`, add the reaction bar. Also add hover tracking and the smiley overlay.

The updated `body` should be:

```swift
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                    if message.isOutgoing {
                        outgoingBubble
                    } else {
                        incomingBubble
                    }

                    if !message.reactions.isEmpty {
                        reactionBar
                    }
                }

                if isHovered && !showQuickReact && !showEmojiPicker {
                    Button(action: { showQuickReact = true }) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $showQuickReact, arrowEdge: .top) {
                QuickReactBar(
                    onReact: { emoji in
                        showQuickReact = false
                        react(emoji)
                    },
                    onOpenPicker: {
                        showQuickReact = false
                        showEmojiPicker = true
                    }
                )
            }
            .popover(isPresented: $showEmojiPicker, arrowEdge: .top) {
                EmojiPickerView { emoji in
                    showEmojiPicker = false
                    react(emoji)
                }
            }

            if !message.readReceipts.isEmpty {
                HStack {
                    Spacer()
                    ReadReceiptsView(receipts: message.readReceipts, homeserverURL: homeserverURL)
                }
            }
        }
        .contextMenu {
            Button("React...") {
                showEmojiPicker = true
            }
        }
    }
```

- [ ] **Step 3: Add reaction bar and react helper**

Add these to the struct:

```swift
    private var reactionBar: some View {
        ReactionBarView(
            reactions: message.reactions,
            onToggle: { emoji in react(emoji) },
            onAddReaction: { showEmojiPicker = true }
        )
    }

    private func react(_ emoji: String) {
        RecentReactions.shared.recordReaction(emoji)
        onToggleReaction(emoji)
    }
```

- [ ] **Step 4: Update TimelineView to pass the callback**

In `Neb/Views/Timeline/TimelineView.swift`, update the `MessageBubbleView` constructor to pass `onToggleReaction`. The `TimelineViewModel` needs a `toggleReaction` method. 

In `NebCore/Sources/NebCore/ViewModels/TimelineViewModel.swift`, add:

```swift
    public func toggleReaction(eventID: String, emoji: String) async {
        do {
            try await roomService.toggleReaction(roomID: roomID, eventID: eventID, emoji: emoji)
        } catch {}
    }
```

In `TimelineView`, update the `MessageBubbleView` call:

```swift
MessageBubbleView(
    message: message,
    groupPosition: groupPosition(isFirst: first, isLast: last),
    isDM: isDM,
    homeserverURL: homeserverURL,
    onToggleReaction: { emoji in
        Task { await viewModel.toggleReaction(eventID: message.id, emoji: emoji) }
    }
)
```

- [ ] **Step 5: Build**

```bash
cd /Users/mattog/dev/matto/neb/NebCore && swift build
```

Fix any compilation errors. Regenerate Xcode project if needed:

```bash
cd /Users/mattog/dev/matto/neb && xcodegen generate
```

- [ ] **Step 6: Commit**

```bash
git add Neb/Views/Timeline/MessageBubbleView.swift \
       Neb/Views/Timeline/TimelineView.swift \
       NebCore/Sources/NebCore/ViewModels/TimelineViewModel.swift
git commit -m "feat: wire reactions into message bubbles with hover, quick bar, and full picker"
```

---

## Task 8: Integration Test

**Files:** None — manual verification.

- [ ] **Step 1: Regenerate and build**

```bash
cd /Users/mattog/dev/matto/neb
xcodegen generate
```

Build and run in Xcode.

- [ ] **Step 2: Verify existing reactions display**

Open a room that has reactions on messages (react from Element X first if needed). Verify reaction pills show below messages with correct emoji and count. Verify `includesMe` pills are tinted.

- [ ] **Step 3: Verify hover → quick react → full picker flow**

1. Hover a message → smiley appears at top-right
2. Click smiley → quick react bar appears with 6 emoji + "+"
3. Click an emoji → reaction is sent, bar dismisses
4. Click "+" → full picker opens with categories and search
5. Search for an emoji → results filter
6. Click emoji in picker → reaction sent, picker closes

- [ ] **Step 4: Verify toggle behavior**

Click a reaction pill you already reacted with → your reaction is removed. Click it again → re-added.

- [ ] **Step 5: Verify right-click**

Right-click a message → "React..." opens the full picker.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: reaction integration adjustments"
```
