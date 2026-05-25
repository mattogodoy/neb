import SwiftUI
import NebCore

struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let roomName: String
    var directUserID: String?
    var cryptoServiceProvider: (() -> any CryptoServiceProtocol)?
    var isDM: Bool = false
    var homeserverURL: String = ""
    @State private var showVerification = false
    @State private var isContactVerified = false
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }

                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            let prev = index > 0 ? viewModel.messages[index - 1] : nil
                            let next = index < viewModel.messages.count - 1 ? viewModel.messages[index + 1] : nil
                            let first = isFirstInGroup(current: message, previous: prev)
                            let last = isLastInGroup(current: message, next: next)

                            if shouldShowDaySeparator(current: message, previous: prev) {
                                DaySeparatorView(date: message.timestamp)
                            }

                            MessageBubbleView(
                                message: message,
                                groupPosition: groupPosition(isFirst: first, isLast: last),
                                isDM: isDM,
                                homeserverURL: homeserverURL,
                                onToggleReaction: { emoji in
                                    Task { await viewModel.toggleReaction(eventID: message.id, emoji: emoji) }
                                },
                                onEdit: message.isEditable ? {
                                    viewModel.editingMessage = message
                                    viewModel.composerText = message.body
                                } : nil
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, first ? 8 : 2)
                            .id(message.id)
                        }

                        if !viewModel.typingUsers.isEmpty {
                            TypingIndicatorView(users: viewModel.typingUsers)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .transition(.opacity)
                                .id("typing-indicator")
                        }
                        Color.clear.frame(height: 1)
                            .id("scroll-bottom")
                    }
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    let atBottom = geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 50
                    return atBottom
                } action: { _, newValue in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isAtBottom = newValue
                    }
                }
                .onChange(of: viewModel.messages.last?.id) { _, newID in
                    if let id = newID, isAtBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.typingUsers.isEmpty) { _, isEmpty in
                    if !isEmpty && isAtBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }

                if !isAtBottom {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("scroll-bottom", anchor: .bottom)
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(.darkGray))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            }

            Divider()

            MessageComposerView(viewModel: viewModel)
        }
        .navigationTitle(roomName)
        .toolbar {
            if let _ = directUserID, cryptoServiceProvider != nil {
                ToolbarItem {
                    Button(action: { showVerification = true }) {
                        Label(
                            isContactVerified ? "\(roomName) Verified" : "Verify \(roomName)",
                            systemImage: isContactVerified ? "person.badge.shield.checkmark.fill" : "person.badge.shield.checkmark"
                        )
                        .foregroundStyle(isContactVerified ? .green : .orange)
                    }
                }
            }
        }
        .sheet(isPresented: $showVerification) {
            if let provider = cryptoServiceProvider, let userID = directUserID {
                ContactVerificationView(
                    viewModel: VerificationViewModel(cryptoService: provider()),
                    userID: userID,
                    displayName: roomName,
                    cryptoService: provider()
                )
            }
        }
        .task {
            await viewModel.markAsRead()
            await checkContactVerification()
        }
        .onChange(of: showVerification) { _, isShowing in
            if !isShowing {
                Task { await checkContactVerification() }
            }
        }
    }

    private func checkContactVerification() async {
        guard let userID = directUserID, let provider = cryptoServiceProvider else { return }
        isContactVerified = await provider().isUserVerified(userID: userID)
    }

    private func isFirstInGroup(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        if prev.senderID != current.senderID { return true }
        if current.timestamp.timeIntervalSince(prev.timestamp) > 300 { return true }
        if !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp) { return true }
        return false
    }

    private func isLastInGroup(current: NebMessage, next: NebMessage?) -> Bool {
        guard let next = next else { return true }
        if next.senderID != current.senderID { return true }
        if next.timestamp.timeIntervalSince(current.timestamp) > 300 { return true }
        if !Calendar.current.isDate(next.timestamp, inSameDayAs: current.timestamp) { return true }
        return false
    }

    private func groupPosition(isFirst: Bool, isLast: Bool) -> MessageGroupPosition {
        switch (isFirst, isLast) {
        case (true, true): return .alone
        case (true, false): return .first
        case (false, true): return .last
        case (false, false): return .middle
        }
    }

    private func shouldShowDaySeparator(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        return !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp)
    }
}
