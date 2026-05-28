import SwiftUI
import NebCore

struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let roomName: String
    var directUserID: String?
    var securityServiceProvider: (() -> any SecurityProtocol)?
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

                        ForEach(viewModel.messages) { message in
                            let layout = viewModel.messageLayouts[message.id]

                            if message.id == firstUnreadMessageID {
                                newMessagesSeparator
                                    .id(ScrollTarget.newSeparator)
                            }

                            if layout?.showDaySeparator ?? true {
                                DaySeparatorView(date: message.timestamp)
                            }

                            MessageBubbleView(
                                message: message,
                                groupPosition: layout?.groupPosition ?? .alone,
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
                            .padding(.top, (layout?.groupPosition == .first || layout?.groupPosition == .alone) ? 8 : 2)
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
            if let _ = directUserID, securityServiceProvider != nil {
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
            if let provider = securityServiceProvider, let userID = directUserID {
                ContactVerificationView(
                    viewModel: VerificationViewModel(securityService: provider()),
                    userID: userID,
                    displayName: roomName,
                    securityService: provider()
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
        for _ in 0..<100 {
            if viewModel.hasLoadedInitialTimeline { return viewModel.messages }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .milliseconds(50))
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
        guard let userID = directUserID, let provider = securityServiceProvider else { return }
        isContactVerified = await provider().isUserVerified(userID: userID)
    }

}
