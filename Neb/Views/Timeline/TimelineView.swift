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

                            if shouldShowDaySeparator(current: message, previous: prev) {
                                DaySeparatorView(date: message.timestamp)
                            }

                            MessageBubbleView(
                                message: message,
                                isFirstInGroup: isFirstInGroup(current: message, previous: prev),
                                isDM: isDM,
                                homeserverURL: homeserverURL
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, isFirstInGroup(current: message, previous: prev) ? 8 : 2)
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
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

    private func shouldShowDaySeparator(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        return !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp)
    }
}
