import SwiftUI
import NebCore

struct ReadReceiptsView: View {
    let receipts: [ReadReceipt]
    let homeserverURL: String
    private let maxVisible = 3
    private let size: CGFloat = 14

    var body: some View {
        if !receipts.isEmpty {
            HStack(spacing: -4) {
                ForEach(Array(receipts.prefix(maxVisible).enumerated()), id: \.element.userID) { index, receipt in
                    AvatarView(
                        size: size,
                        name: receipt.displayName,
                        userID: receipt.userID,
                        avatarURL: receipt.avatarURL,
                        homeserverURL: homeserverURL
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.windowBackgroundColor), lineWidth: 1)
                    )
                    .zIndex(Double(maxVisible - index))
                }

                if receipts.count > maxVisible {
                    Text("+\(receipts.count - maxVisible)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}
