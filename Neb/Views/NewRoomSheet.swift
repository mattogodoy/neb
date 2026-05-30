import SwiftUI
import NebCore

struct NewRoomSheet: View {
    @Bindable var viewModel: NewRoomViewModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Room")
                .font(.headline)

            TextField("Room name", text: $viewModel.roomName)
                .textFieldStyle(.roundedBorder)

            TextField("Invite users (comma-separated, e.g. @alice:matrix.org, @bob:matrix.org)", text: $viewModel.inviteUserIDs)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create Room") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canCreate)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func create() {
        Task {
            if let roomID = await viewModel.createRoom() {
                onCreated(roomID)
                dismiss()
            }
        }
    }
}
