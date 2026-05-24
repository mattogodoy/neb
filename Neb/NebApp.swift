import SwiftUI
import NebCore

@main
struct NebApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.loginViewModel.authState {
                case .loggedIn:
                    if let roomListVM = appState.roomListViewModel {
                        MainView(
                            roomListViewModel: roomListVM,
                            roomServiceProvider: { appState.makeRoomService() },
                            cryptoServiceProvider: { appState.makeCryptoService() }
                        )
                    } else {
                        ProgressView("Starting sync...")
                    }
                default:
                    LoginView(viewModel: appState.loginViewModel)
                }
            }
            .task {
                let restored = await appState.loginViewModel.tryRestoreSession()
                if restored {
                    await appState.onLoggedIn()
                }
            }
            .onChange(of: appState.loginViewModel.authState) { _, newState in
                Task {
                    switch newState {
                    case .loggedIn:
                        await appState.onLoggedIn()
                    case .loggedOut:
                        await appState.onLoggedOut()
                    default:
                        break
                    }
                }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Direct Message") {
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
