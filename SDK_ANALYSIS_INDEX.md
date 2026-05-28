# Matrix Rust SDK Analysis - Complete Index

This directory contains comprehensive documentation of the Matrix Rust SDK (v26.5.13) capabilities and Neb's current usage.

## Files in This Analysis

### 1. SDK_CAPABILITIES.md (9.3 KB)
**High-level overview of what the SDK offers vs what Neb uses**

Content:
- Executive summary (Neb uses ~15% of SDK capabilities)
- 6 categories of currently used features (~45 methods)
- Breakdown of unused features by category (~400+ methods available)
- SDK architecture explanation
- Performance notes and caveats
- Untapped opportunities ranked by effort
- Quick reference table for all adapters

**Best for:** Understanding what's possible without diving into details

### 2. SDK_TECHNICAL_REFERENCE.md (15 KB)
**Detailed technical reference with method signatures and enums**

Content:
- Complete method signatures for all major SDK classes
- All enum definitions and their cases
- Listener/callback protocol definitions
- Paginated iterator descriptions
- Summary table of ~155 documented methods
- Helper functions

Classes documented in detail:
- Client (21 methods)
- ClientBuilder (8 methods)
- Room (40+ methods)
- Timeline (20+ methods)
- Encryption (15+ methods)
- SessionVerificationController (10+ methods)
- Plus RoomListService, SyncService, and others

**Best for:** Looking up specific method signatures and options

---

## Quick Navigation

### "How much of the SDK does Neb use?"
→ Start with **SDK_CAPABILITIES.md**, Executive Summary

### "What methods does Client.X have?"
→ Check **SDK_TECHNICAL_REFERENCE.md**, search for class name

### "Can the SDK do feature X?"
→ Search both documents for feature name, or check SDK_CAPABILITIES.md sections

### "What should we build next?"
→ SDK_CAPABILITIES.md → "Untapped Opportunities" section

### "What happens when I call Room.setName()?"
→ SDK_TECHNICAL_REFERENCE.md → Room class section

---

## Key Findings

### Current Usage (5 Domains)
1. **Authentication** - login, restore, logout (6 methods)
2. **Sync & Room List** - streaming room updates (7 methods)
3. **Room Operations** - get room, create room, members (8 methods)
4. **Timeline & Messages** - send, edit, react, paginate (10 methods)
5. **Encryption & Verification** - device/user verification (12 methods)
6. **Typing Notifications** - typing indicators (3 methods)

### Unused But Available (10+ Domains)
1. **Room State Management** - 25+ methods (topic, alias, power levels, etc.)
2. **Rich Messages** - 20+ types (files, images, polls, replies, location)
3. **Media Management** - uploads, downloads, thumbnails
4. **Search** - full-text search across rooms
5. **Account Management** - profile, presence, device management
6. **Advanced Encryption** - backup, recovery codes, cross-signing chains
7. **VoIP & Calls** - call signaling and management
8. **Spaces** - hierarchical room organization
9. **Push Notifications** - server-side notification rules
10. **Drafts** - message draft persistence

---

## High-Impact Next Features

### Quick Wins (1-2 weeks)
- Message search (in-room text search)
- Room info view (display topic, members)
- Presence indicator (online status)
- Message deletion (redact messages)

### Medium Effort (2-4 weeks)
- File uploads (images, videos, documents)
- Room settings UI (edit topic, avatar)
- Member management (invite, kick, ban)
- Message replies (threaded conversations)
- Account profile (edit display name)

### Larger Projects (4+ weeks)
- Full search UI (room discovery, message search)
- Voice calling (WebRTC integration)
- Spaces (hierarchical organization)
- Polls (voting system)
- Location sharing (live location updates)

---

## Adapter Reference

| File | Implements | SDK Classes Used |
|------|-----------|------------------|
| MatrixAuthAdapter.swift | AuthServiceProtocol | Client, ClientBuilder, Session |
| MatrixSyncAdapter.swift | SyncServiceProtocol | SyncService, RoomListService, RoomList, Room |
| MatrixRoomAdapter.swift | RoomServiceProtocol | Room, Timeline, TimelineItem, Event |
| MatrixCryptoAdapter.swift | CryptoServiceProtocol | Encryption, SessionVerificationController |
| MatrixTypingAdapter.swift | TypingServiceProtocol | Room, TypingNotificationsListener |
| MatrixNotificationAdapter.swift | NotificationServiceProtocol | UNUserNotificationCenter (macOS native) |

---

## SDK Source Locations

### Installed SDK Source
```
/Users/mormubis/workspace/neb/NebCore/.build/checkouts/matrix-rust-components-swift/
```

### SDK Files
- `Sources/MatrixRustSDK/matrix_sdk_ffi.swift` (54,600 lines - FFI bindings)
- `Sources/MatrixRustSDK/matrix_sdk.swift` (2,466 lines - Swift wrappers)
- `Sources/MatrixRustSDK/matrix_sdk_base.swift` (919 lines)
- `Sources/MatrixRustSDK/matrix_sdk_crypto.swift` (1,852 lines)
- `Sources/MatrixRustSDK/matrix_sdk_ui.swift` (1,235 lines)
- `Sources/MatrixRustSDK/matrix_sdk_common.swift` (734 lines)
- `Examples/Walkthrough.swift` - Complete example of login, sync, timeline

### Neb Integration
- `NebCore/Sources/NebCore/Adapters/` - 6 adapter files (600+ lines)
- `NebCore/Sources/NebCore/Services/` - 6 protocol definitions (100 lines)
- `Neb/AppState.swift` - Dependency wiring

---

## Reading Order

For different audiences:

**Product/Design:** Start with SDK_CAPABILITIES.md → "Untapped Opportunities"

**New Contributors:** 
1. CLAUDE.md (architecture overview)
2. SDK_CAPABILITIES.md (what SDK can do)
3. NebCore/Sources/NebCore/Adapters/ (how it's used)

**Feature Implementation:**
1. SDK_TECHNICAL_REFERENCE.md (method signatures)
2. SDK examples in .build/checkouts/...Examples/
3. Relevant adapter file
4. Look for similar functionality in codebase

**SDK Deep Dive:**
1. Both documents in this folder
2. matrix_sdk_ffi.swift (raw SDK types)
3. Examples/Walkthrough.swift
4. Rust SDK repo: github.com/matrix-org/matrix-rust-sdk

---

## Key SDK Concepts

### Listeners & Streaming
The SDK uses callback listeners to stream real-time updates:
- `RoomListEntriesListener` → room list changes
- `TimelineListener` → new messages, edits, reactions
- `TypingNotificationsListener` → users typing
- `VerificationStateListener` → verification changes

**Important:** Listeners must be retained as instance properties in adapters, or they'll be deallocated and cause crashes.

### Async/Await Pattern
Almost all SDK operations are async:
```swift
try await client.login(...)
try await room.timeline()
try await timeline.send(msg: content)
```

### Event Streaming
Both room list and timeline use diff-based updates:
```swift
// Not "here's the new list", but "append 3 items, remove 1 item, etc."
case .append(values: [Room])
case .remove(index: UInt32)
```

This is memory-efficient for large lists.

### Sliding Sync
Neb uses `.discoverNative` sliding sync, which:
- Only downloads room list metadata you need
- Supports pagination of room lists
- Reduces initial sync time
- Requires explicit room subscription before timeline works

---

## Performance Notes

From CLAUDE.md:
- **First login** with fresh crypto: 1-2 minutes (crypto key generation)
- **Session restore** with cached crypto: ~seconds
- **Cross-signing**: Enabled automatically on first login
- **Key backup**: Enabled automatically on first login
- **Crypto store**: Lives in `~/Library/Containers/com.neb.app/Data/Library/Application Support/Neb/data/`
- **Media caching**: In-memory only (NSCache in AvatarImageCache)
- **Room list debouncing**: 100ms to avoid redundant async fetches

---

## Debugging Tips

If something doesn't work in an adapter:

1. **Check listener retention** - make sure it's a property, not local var
2. **Check room subscription** - timeline won't emit until room is subscribed
3. **Check encryption** - first login takes time for crypto init
4. **Check session** - session.json must be valid for restore
5. **Check methods** - some Room methods require async context

---

## Related Files in Neb

- `CLAUDE.md` - Architecture & patterns
- `NebCore/Package.swift` - SDK dependency (v26.5.13+)
- `project.yml` - Xcode project generation
- `Neb/Views/` - UI layer using adapters
- `NebCore/Sources/NebCore/ViewModels/` - Business logic

---

## External Resources

- **Matrix Spec**: https://spec.matrix.org/latest/
- **Matrix Rust SDK**: https://github.com/matrix-org/matrix-rust-sdk
- **Swift SDK Package**: https://github.com/matrix-org/matrix-rust-components-swift
- **Matrix Homeserver**: https://matrix.matto.io (Neb's default)

---

## Document Maintenance

These documents were generated by analyzing:
- Neb's adapter implementations
- SDK source code (matrix_sdk_*.swift files)
- SDK examples
- Live exploration of installed SDK

If SDK version changes (in Package.swift), regenerate by:
1. Delete cached analysis
2. Run `swift build` in NebCore
3. Inspect new files in `.build/checkouts/matrix-rust-components-swift/`
4. Update method lists

---

Generated: 2026-05-27  
SDK Version: 26.5.13  
Neb Architecture: NebCore library + SwiftUI app

