import SwiftUI
import NebCore

struct AvatarView: View {
    let size: CGFloat
    let name: String
    let userID: String
    var avatarURL: String?
    var homeserverURL: String = ""

    @State private var loadedImage: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(UserColorGenerator.color(for: userID))
                .frame(width: size, height: size)

            Text(initial)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)

            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .task(id: avatarURL) {
            guard let url = avatarURL, !url.isEmpty else { return }
            if let image = await AvatarImageCache.shared.image(for: url) {
                withAnimation(.easeIn(duration: 0.15)) {
                    loadedImage = image
                }
            }
        }
    }

    private var initial: String {
        let cleaned = name.drop(while: { $0 == "@" || $0 == "!" || $0 == "#" })
        if let first = cleaned.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
