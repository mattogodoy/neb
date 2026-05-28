import SwiftUI
import NebCore

@main
struct NebApp: App {
    @State private var appState = AppState()
    @State private var isRestoringSession = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isRestoringSession {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Neb")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 400, height: 350)
                } else {
                    switch appState.loginViewModel.authState {
                    case .loggedIn:
                        if let roomListVM = appState.roomListViewModel {
                            MainView(
                                roomListViewModel: roomListVM,
                                timelineServiceProvider: { appState.makeTimelineService() },
                                roomsServiceProvider: { appState.makeRoomsService() },
                                securityServiceProvider: { appState.makeSecurityService() },
                                typingServiceProvider: { appState.makeTypingService() },
                                currentUserID: appState.currentUserID,
                                database: appState.database,
                                deviceVerificationStatus: appState.deviceVerificationStatus,
                                homeserverURL: appState.homeserverURL,
                                onLogout: {
                                    Task { await appState.loginViewModel.logout() }
                                }
                            )
                        } else {
                            ProgressView()
                        }
                    default:
                        LoginView(viewModel: appState.loginViewModel)
                    }
                }
            }
            .task {
                let _ = await appState.loginViewModel.tryRestoreSession()
                isRestoringSession = false
            }
            .onChange(of: appState.loginViewModel.authState) { oldState, newState in
                guard oldState != newState else { return }
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
