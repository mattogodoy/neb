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
                    HStack(spacing: 2) {
                        Text(reaction.emoji)
                            .font(.system(size: 12))
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(reaction.includesMe ? .white : .secondary)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
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
        layout(proposal: proposal, subviews: subviews).size
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
