import SwiftUI
import NebCore

struct RoomRowView: View {
    let room: NebRoom
    let homeserverURL: String
    var typingUsers: [NebUser] = []

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

                if !typingUsers.isEmpty {
                    Text(typingText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                } else if let lastMessage = room.lastMessage {
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

    private var typingText: String {
        switch typingUsers.count {
        case 1:
            let name = typingUsers[0].displayName ?? typingUsers[0].id
            return "\(name) is typing..."
        case 2:
            let name1 = typingUsers[0].displayName ?? typingUsers[0].id
            let name2 = typingUsers[1].displayName ?? typingUsers[1].id
            return "\(name1) and \(name2) are typing..."
        default:
            return "Several people are typing..."
        }
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
