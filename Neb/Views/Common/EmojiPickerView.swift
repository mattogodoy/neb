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
                    ForEach(EmojiData.search(searchText)) { item in
                        emojiButton(item.emoji)
                    }
                } else if selectedCategory == "recent" {
                    ForEach(RecentReactions.shared.list, id: \.self) { emoji in
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
