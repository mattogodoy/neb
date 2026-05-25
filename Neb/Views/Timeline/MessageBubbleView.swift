import SwiftUI
import NebCore

enum MessageGroupPosition {
    case alone, first, middle, last
}

struct MessageBubbleView: View {
    let message: NebMessage
    let groupPosition: MessageGroupPosition
    let isDM: Bool
    let homeserverURL: String
    let onToggleReaction: (String) -> Void

    @State private var isHovered = false
    @State private var showQuickReact = false
    @State private var showEmojiPicker = false

    private let avatarSize: CGFloat = 28

    private var isFirst: Bool { groupPosition == .first || groupPosition == .alone }
    private var isLast: Bool { groupPosition == .last || groupPosition == .alone }

    var body: some View {
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
            }
        }
        .contextMenu {
            Button("React...") {
                showEmojiPicker = true
            }
        }
    }

    private func react(_ emoji: String) {
        RecentReactions.shared.recordReaction(emoji)
        onToggleReaction(emoji)
    }

    // MARK: - Outgoing

    private var outgoingBubble: some View {
        HStack {
            Spacer(minLength: 60)
            bubbleWithHover(smileyOnLeft: true) {
                outgoingBubbleContent
                    .background(Color.accentColor.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(BubbleShape(
                        topLeft: 12,
                        topRight: isFirst ? 12 : 2,
                        bottomLeft: 12,
                        bottomRight: isLast ? 12 : 2
                    ))
            }
        }
    }

    private var outgoingBubbleContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(message.body)
                .font(.system(size: 13))

            HStack(spacing: 2) {
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))

                if message.readReceipts.isEmpty {
                    sendStatusIcon
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sendStatusIcon: some View {
        switch message.sendStatus {
        case .sending:
            ProgressView()
                .controlSize(.mini)
        case .sent:
            Text("✓")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Incoming

    private var incomingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isDM {
                if isFirst {
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
                if isFirst && !isDM {
                    Text(message.senderDisplayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UserColorGenerator.color(for: message.senderID))
                }

                bubbleWithHover(smileyOnLeft: false) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(message.body)
                            .font(.system(size: 13))

                        Text(message.timestamp, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .foregroundStyle(.primary)
                    .clipShape(BubbleShape(
                        topLeft: isFirst ? 12 : 2,
                        topRight: 12,
                        bottomLeft: isLast ? 12 : 2,
                        bottomRight: 12
                    ))
                }
            }

            Spacer(minLength: 60)
        }
    }

    // MARK: - Hover + Popovers (anchored to bubble)

    private func bubbleWithHover<Content: View>(smileyOnLeft: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            if smileyOnLeft && isHovered && !showQuickReact && !showEmojiPicker {
                smileyButton
            } else if smileyOnLeft {
                Color.clear.frame(width: 22, height: 22)
            }

            content()

            if !smileyOnLeft && isHovered && !showQuickReact && !showEmojiPicker {
                smileyButton
            } else if !smileyOnLeft {
                Color.clear.frame(width: 22, height: 22)
            }
        }
        .onHover { isHovered = $0 }
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
    }

    private var smileyButton: some View {
        Button(action: { showQuickReact = true }) {
            Image(systemName: "smiley")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }
}

private struct BubbleShape: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight), radius: topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY), radius: topLeft)
        path.closeSubpath()
        return path
    }
}
