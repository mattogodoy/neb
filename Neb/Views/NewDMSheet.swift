import SwiftUI
import NebCore

struct NewDMSheet: View {
    @Bindable var viewModel: NewDMViewModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Direct Message")
                .font(.headline)

            TextField("@user:homeserver.com", text: $viewModel.userID)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if viewModel.canCreate {
                        create()
                    }
                }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Start Chat") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canCreate)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func create() {
        Task {
            if let roomID = await viewModel.createDM() {
                onCreated(roomID)
                dismiss()
            }
        }
    }
}
