import AppKit
import Observation
import ServiceManagement
import SwiftUI

private let mainWindowID = "main-window"

@MainActor
@Observable
final class AppPreferences {
    var launchAtLoginEnabled = false
    var launchAtLoginSupported = false
    var launchAtLoginError: String?

    init() {
        refreshLaunchAtLoginState()
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginError = nil

        guard supportsLaunchAtLogin else {
            launchAtLoginSupported = false
            launchAtLoginEnabled = false
            launchAtLoginError = "Launch at Login is unavailable in `swift run`. Open WorktreeDesk.app to enable it."
            return
        }

        launchAtLoginSupported = true
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginError = "Allow WorktreeDesk in System Settings > General > Login Items."
        case .notRegistered, .notFound:
            launchAtLoginEnabled = false
        @unknown default:
            launchAtLoginEnabled = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard supportsLaunchAtLogin else {
            launchAtLoginEnabled = false
            launchAtLoginSupported = false
            launchAtLoginError = "Launch at Login is unavailable in `swift run`. Open WorktreeDesk.app to enable it."
            return
        }

        launchAtLoginError = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshLaunchAtLoginState()
            if launchAtLoginEnabled != enabled {
                launchAtLoginError = "Could not update Launch at Login for this build."
            }
        } catch {
            let message = launchAtLoginMessage(for: error)
            refreshLaunchAtLoginState()
            launchAtLoginError = message
        }
    }

    private var supportsLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private func launchAtLoginMessage(for error: Error) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if rawMessage.localizedCaseInsensitiveContains("invalid argument") {
            return "Launch at Login requires an installed app bundle. Open WorktreeDesk.app to enable it."
        }
        return rawMessage
    }
}

final class WorktreeDeskAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct WorktreeDeskApp: App {
    @NSApplicationDelegateAdaptor(WorktreeDeskAppDelegate.self) private var appDelegate
    @State private var viewModel = WorktreeViewModel(repositoryStore: RepositoryStore())
    @State private var appPreferences = AppPreferences()

    var body: some Scene {
        Window("WorktreeDesk", id: mainWindowID) {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandMenu("Repository") {
                Button("Add Repository…") {
                    viewModel.pickRepositoryFolder(activateApp: true)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Toggle Favorite") {
                    viewModel.toggleFavoriteSelectedRepository()
                }
                .disabled(viewModel.selectedRepositoryID == nil)

                Button("Refresh Worktrees") {
                    Task {
                        await viewModel.refreshWorktrees()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Worktree") {
                Button("New Worktree…") {
                    viewModel.openCreateWorktreeSheet()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Prune Stale Worktrees") {
                    Task {
                        await viewModel.prune()
                    }
                }
            }
        }

        MenuBarExtra("WorktreeDesk", systemImage: "point.3.connected.trianglepath.dotted") {
            MenuBarPanel(viewModel: viewModel, appPreferences: appPreferences)
        }
    }
}

private struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var viewModel: WorktreeViewModel
    @Bindable var appPreferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WorktreeDesk")
                .font(.headline)

            Button("Open Main Window") {
                focusMainWindow()
            }

            Button("Add Repository…") {
                Task {
                    focusMainWindow()
                    try? await Task.sleep(for: .milliseconds(120))
                    viewModel.pickRepositoryFolder(activateApp: true)
                }
            }

            if viewModel.selectedRepositoryID == nil {
                Text("No repository selected")
                    .foregroundStyle(.secondary)
            } else {
                Divider()

                if viewModel.worktrees.isEmpty {
                    Text("No worktrees found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.filteredWorktrees.prefix(8))) { worktree in
                        Button("\(worktree.branchName) • \(worktree.folderName)") {
                            Task {
                                await viewModel.open(worktree: worktree, in: viewModel.selectedOpenTarget)
                            }
                        }
                    }
                }

                Divider()

                Button("Refresh") {
                    Task {
                        await viewModel.refreshWorktrees()
                    }
                }

                Button("New Worktree…") {
                    focusMainWindow()
                    viewModel.openCreateWorktreeSheet()
                }
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { appPreferences.launchAtLoginEnabled },
                set: { appPreferences.setLaunchAtLogin($0) }
            ))
            .disabled(!appPreferences.launchAtLoginSupported)

            if let launchAtLoginError = appPreferences.launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit WorktreeDesk", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
        .task {
            await viewModel.refreshWorktrees()
            appPreferences.refreshLaunchAtLoginState()
        }
    }

    private func focusMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
}
