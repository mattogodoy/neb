import SwiftUI
import NebCore

struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let roomName: String
    var cryptoServiceProvider: (() -> any CryptoServiceProtocol)?
    @State private var showVerification = false

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
            if cryptoServiceProvider != nil {
                ToolbarItem {
                    Button(action: { showVerification = true }) {
                        Image(systemName: "checkmark.shield")
                    }
                    .help("Verify Contact")
                }
            }
        }
        .sheet(isPresented: $showVerification) {
            if let provider = cryptoServiceProvider {
                ContactVerificationView(
                    viewModel: VerificationViewModel(cryptoService: provider()),
                    contactName: roomName
                )
            }
        }
        .task {
            await viewModel.markAsRead()
        }
    }
}
