import SwiftUI

struct ConnectionBanner: View {
    let isOnline: Bool

    var body: some View {
        if !isOnline {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }
}
