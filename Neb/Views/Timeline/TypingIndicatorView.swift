import SwiftUI
import NebCore

struct TypingIndicatorView: View {
    let users: [NebUser]
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            Text(typingText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .italic()

            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .offset(y: animating ? -3 : 0)
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }

    private var typingText: String {
        switch users.count {
        case 1:
            let name = users[0].displayName ?? users[0].id
            return "\(name) is typing"
        case 2:
            let name1 = users[0].displayName ?? users[0].id
            let name2 = users[1].displayName ?? users[1].id
            return "\(name1) and \(name2) are typing"
        default:
            return "Several people are typing"
        }
    }
}
