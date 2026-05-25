import SwiftUI
import NebCore

struct LoginView: View {
    @Bindable var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Neb")
                .font(.largeTitle)
                .fontWeight(.bold)

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Logging in and setting up encryption...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("This may take a minute on first login.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(spacing: 12) {
                    TextField("Homeserver URL", text: $viewModel.homeserver)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)

                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)

                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit {
                            if viewModel.canLogin {
                                Task { await viewModel.login() }
                            }
                        }
                }
                .frame(maxWidth: 300)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button("Log In") {
                    Task { await viewModel.login() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canLogin)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(40)
        .frame(width: 400, height: 350)
    }
}
