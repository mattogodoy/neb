import SwiftUI
import NebCore

struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let roomName: String
    var directUserID: String?
    var privacyServiceProvider: (() -> any PrivacyProtocol)?
    var isDM: Bool = false
    var homeserverURL: String = ""
    @State private var showVerification = false
    @State private var isContactVerified = false
    @State private var firstUnreadMessageID: String?
    @State private var hasSetupComplete = false
    @State private var scrollCorrectionTask: Task<Void, Never>?

    private enum ScrollTarget {
        static let newSeparator = "new-separator"
        static let bottom = "timeline-bottom"
    }

    var body: some View {
        VStack(spacing: 0) {
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

                            if message.id == firstUnreadMessageID {
                                newMessagesSeparator
                                    .id(ScrollTarget.newSeparator)
                            }

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
                    }
                    .padding(.vertical, 8)

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollTarget.bottom)
                }
                .defaultScrollAnchor(.bottom)
                .opacity(hasSetupComplete ? 1 : 0)
                .task {
                    await scrollToInitialPosition(with: proxy)
                }
                .onChange(of: viewModel.messages.last?.id) { oldID, newID in
                    scrollAfterLiveMessageIfNeeded(from: oldID, to: newID, with: proxy)
                }
            }

            Divider()

            MessageComposerView(viewModel: viewModel)
        }
        .navigationTitle(roomName)
        .toolbar {
            if let _ = directUserID, privacyServiceProvider != nil {
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
            if let provider = privacyServiceProvider, let userID = directUserID {
                ContactVerificationView(
                    viewModel: VerificationViewModel(privacyService: provider()),
                    userID: userID,
                    displayName: roomName,
                    privacyService: provider()
                )
            }
        }
        .task {
            await checkContactVerification()
        }
        .onDisappear {
            scrollCorrectionTask?.cancel()
            scrollCorrectionTask = nil
        }
        .onChange(of: showVerification) { _, isShowing in
            if !isShowing {
                Task { await checkContactVerification() }
            }
        }
    }

    private var newMessagesSeparator: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(height: 1)
            Text("NEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @MainActor
    private func scrollToInitialPosition(with proxy: ScrollViewProxy) async {
        scrollCorrectionTask?.cancel()
        scrollCorrectionTask = nil

        let messages = await waitForInitialTimelineLoad()
        guard !Task.isCancelled else { return }

        firstUnreadMessageID = firstUnreadID(in: messages)

        // Let SwiftUI materialize the bottom marker or NEW separator without delaying display.
        await Task.yield()
        guard !Task.isCancelled else { return }

        if firstUnreadMessageID != nil {
            proxy.scrollTo(ScrollTarget.newSeparator, anchor: .top)
        } else {
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }

        hasSetupComplete = true
        await viewModel.markAsRead()
    }

    @MainActor
    private func waitForInitialTimelineLoad() async -> [NebMessage] {
        for _ in 0..<80 {
            guard !Task.isCancelled else { return viewModel.messages }

            if viewModel.hasLoadedInitialTimeline {
                return viewModel.messages
            }

            try? await Task.sleep(for: .milliseconds(25))
        }

        return viewModel.messages
    }

    private func firstUnreadID(in messages: [NebMessage]) -> String? {
        let unread = Int(viewModel.initialUnreadCount)
        guard unread > 0, unread < messages.count else { return nil }
        let index = messages.count - unread
        return messages[index].id
    }

    private func scrollAfterLiveMessageIfNeeded(from oldID: String?, to newID: String?, with proxy: ScrollViewProxy) {
        guard hasSetupComplete, oldID != newID, let lastMessage = viewModel.messages.last else { return }

        Task { await viewModel.markAsRead() }

        guard lastMessage.isOutgoing else { return }
        firstUnreadMessageID = nil
        scrollCorrectionTask?.cancel()

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }

        scrollCorrectionTask = Task { @MainActor in
            await settleToBottom(with: proxy)
        }
    }

    @MainActor
    private func settleToBottom(with proxy: ScrollViewProxy) async {
        for delay in [50, 150, 300] {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
    }

    private func checkContactVerification() async {
        guard let userID = directUserID, let provider = privacyServiceProvider else { return }
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
