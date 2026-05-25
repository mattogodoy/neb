import SwiftUI

/// Placeholder — full implementation provided by Task 4.
struct AvatarView: View {
    let size: CGFloat
    let name: String
    let userID: String
    let avatarURL: String?
    let homeserverURL: String

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2,
           let first = words.first?.first,
           let second = words[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
