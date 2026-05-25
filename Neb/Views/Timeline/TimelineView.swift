import SwiftUI
import NebCore

struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let roomName: String
    var directUserID: String?
    var cryptoServiceProvider: (() -> any CryptoServiceProtocol)?
    @State private var showVerification = false
    @State private var isContactVerified = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
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
                    displayName: roomName
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
}
