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
