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

    private let avatarSize: CGFloat = 28

    private var isFirst: Bool { groupPosition == .first || groupPosition == .alone }
    private var isLast: Bool { groupPosition == .last || groupPosition == .alone }

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

            if isLast && !message.readReceipts.isEmpty {
                ReadReceiptsView(receipts: message.readReceipts, homeserverURL: homeserverURL)
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

            Spacer(minLength: 60)
        }
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
