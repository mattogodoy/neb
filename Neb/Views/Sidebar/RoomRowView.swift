import SwiftUI
import NebCore

struct RoomRowView: View {
    let room: NebRoom

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(room.isDirect ? Color.blue : Color.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(room.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let lastMessage = room.lastMessage {
                    Text(lastMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
}
