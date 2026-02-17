import AppKit
import SwiftUI

private let mainWindowID = "main-window"

final class WorktreeDeskAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct WorktreeDeskApp: App {
    @NSApplicationDelegateAdaptor(WorktreeDeskAppDelegate.self) private var appDelegate
    @State private var viewModel = WorktreeViewModel(repositoryStore: RepositoryStore())

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
            MenuBarPanel(viewModel: viewModel)
        }
    }
}

private struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var viewModel: WorktreeViewModel

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
        }
        .padding(12)
        .frame(width: 320)
        .task {
            await viewModel.refreshWorktrees()
        }
    }

    private func focusMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
}
