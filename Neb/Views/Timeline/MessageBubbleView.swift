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
