import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: WorktreeViewModel

    @State private var worktreePendingDeletion: WorktreeInfo?
    @State private var showingSelectionDeleteDialog = false

    private var favorites: [RepositoryRecord] {
        viewModel.repositories.filter(\.isFavorite)
    }

    private var recents: [RepositoryRecord] {
        viewModel.repositories.filter { !$0.isFavorite }
    }

    var body: some View {
        NavigationSplitView {
            repositorySidebar
        } detail: {
            detailPanel
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
        .sheet(isPresented: $viewModel.showingCreateSheet) {
            CreateWorktreeSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingCheckoutSheet) {
            CheckoutSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete worktree?",
            isPresented: Binding(
                get: { worktreePendingDeletion != nil },
                set: { newValue in
                    if !newValue {
                        worktreePendingDeletion = nil
                    }
                }
            ),
            presenting: worktreePendingDeletion
        ) { worktree in
            Button("Delete") {
                Task {
                    await viewModel.delete(worktree: worktree, force: false)
                }
            }
            Button("Force Delete", role: .destructive) {
                Task {
                    await viewModel.delete(worktree: worktree, force: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { worktree in
            Text(worktree.path)
        }
        .confirmationDialog(
            "Delete selected worktrees?",
            isPresented: $showingSelectionDeleteDialog
        ) {
            Button(deleteSelectionButtonTitle) {
                Task {
                    await viewModel.deleteSelected(force: false)
                }
            }
            Button("Force Delete Selected", role: .destructive) {
                Task {
                    await viewModel.deleteSelected(force: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(viewModel.selectedWorktreeCount) selected worktree\(viewModel.selectedWorktreeCount == 1 ? "" : "s").")
        }
        .task {
            await viewModel.refreshWorktrees()
        }
    }

    private var repositorySidebar: some View {
        List(selection: Binding(
            get: { viewModel.selectedRepositoryID },
            set: { viewModel.setSelectedRepository(id: $0) }
        )) {
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { repository in
                        RepositoryRow(repository: repository)
                            .tag(Optional(repository.id))
                            .contextMenu {
                                Button(repository.isFavorite ? "Remove Favorite" : "Add Favorite") {
                                    viewModel.toggleFavorite(repositoryID: repository.id)
                                }
                                Button("Remove Repository", role: .destructive) {
                                    viewModel.removeRepository(id: repository.id)
                                }
                            }
                    }
                }
            }

            Section(favorites.isEmpty ? "Repositories" : "Recent") {
                ForEach(recents) { repository in
                    RepositoryRow(repository: repository)
                        .tag(Optional(repository.id))
                        .contextMenu {
                            Button("Add Favorite") {
                                viewModel.toggleFavorite(repositoryID: repository.id)
                            }
                            Button("Remove Repository", role: .destructive) {
                                viewModel.removeRepository(id: repository.id)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Repositories")
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.pickRepositoryFolder()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add repository")

                Button {
                    viewModel.toggleFavoriteSelectedRepository()
                } label: {
                    Image(systemName: "star")
                }
                .disabled(viewModel.selectedRepositoryID == nil)
                .help("Toggle favorite")

                Button {
                    viewModel.removeSelectedRepository()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.selectedRepositoryID == nil)
                .help("Remove repository")
            }
        }
    }

    private var detailPanel: some View {
        Group {
            if let repository = viewModel.selectedRepository {
                VStack(spacing: 0) {
                    header(for: repository)
                    Divider()
                    worktreeTable
                }
                .navigationTitle(repository.name)
            } else {
                ContentUnavailableView(
                    "No repository selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Add or select a repository from the sidebar.")
                )
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search path, branch, folder")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $viewModel.sortMode) {
                        ForEach(WorktreeSortMode.allCases) { sortMode in
                            Text(sortMode.title).tag(sortMode)
                        }
                    }
                } label: {
                    Label("Sort: \(viewModel.sortMode.shortTitle)", systemImage: "arrow.up.arrow.down")
                }
                .help("Controls how worktrees are ordered in the table.")
            }

            ToolbarItem {
                Menu {
                    ForEach(ExternalEditor.allCases) { editor in
                        Button {
                            viewModel.selectedOpenTarget = editor
                        } label: {
                            if editor == viewModel.selectedOpenTarget {
                                Label(editor.rawValue, systemImage: "checkmark")
                            } else {
                                Text(editor.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Default: \(viewModel.selectedOpenTarget.rawValue)", systemImage: "app.badge")
                }
                .help("The Open button and Open Selected actions use this app.")
            }

            ToolbarItem {
                if viewModel.hasSelection {
                    Menu {
                        Button("Fetch Selected") {
                            Task {
                                await viewModel.fetchSelected()
                            }
                        }

                        Button("Pull Selected") {
                            Task {
                                await viewModel.pullSelected()
                            }
                        }

                        Divider()

                        Button("Open Selected in \(viewModel.selectedOpenTarget.rawValue)") {
                            Task {
                                await viewModel.openSelected(in: viewModel.selectedOpenTarget)
                            }
                        }

                        Menu("Open Selected In…") {
                            ForEach(ExternalEditor.allCases) { editor in
                                Button(editor.rawValue) {
                                    Task {
                                        await viewModel.openSelected(in: editor)
                                    }
                                }
                            }
                        }

                        Divider()

                        Button("Checkout Selected…") {
                            viewModel.openCheckoutSheetForSelection()
                        }
                        .disabled(!viewModel.hasSingleSelection)

                        Button("Copy Selected Paths") {
                            viewModel.copySelectedPaths()
                        }

                        Button("Copy Selected Branches") {
                            viewModel.copySelectedBranches()
                        }

                        Divider()

                        Button("Delete Selected…", role: .destructive) {
                            showingSelectionDeleteDialog = true
                        }
                    } label: {
                        Label("\(viewModel.selectedWorktreeCount) Selected", systemImage: "checklist.checked")
                    }
                    .help("Actions for selected worktrees.")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.refreshWorktrees()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.selectedRepositoryID == nil)
                .help("Refresh worktrees")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("New Worktree") {
                    viewModel.openCreateWorktreeSheet()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(viewModel.selectedRepositoryID == nil)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Prune Stale Worktrees") {
                        Task {
                            await viewModel.prune()
                        }
                    }
                    .disabled(viewModel.selectedRepositoryID == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
    }

    private func header(for repository: RepositoryRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(viewModel.filteredWorktrees.count) worktrees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var worktreeTable: some View {
        Table(viewModel.filteredWorktrees, selection: $viewModel.selectedWorktreePaths) {
            TableColumn("Folder") { worktree in
                Text(worktree.folderName)
                    .fontWeight(.semibold)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Branch") { worktree in
                BranchCell(worktree: worktree)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Path") { worktree in
                Text(worktree.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(worktree.path)
            }
            .width(min: 320, ideal: 540)

            TableColumn("Status") { worktree in
                StatusCell(status: worktree.status)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Actions") { worktree in
                WorktreeActionsCell(
                    worktree: worktree,
                    selectedOpenTarget: viewModel.selectedOpenTarget,
                    onFetch: {
                        Task {
                            await viewModel.fetch(worktree: worktree)
                        }
                    },
                    onPull: {
                        Task {
                            await viewModel.pull(worktree: worktree)
                        }
                    },
                    onOpen: {
                        Task {
                            await viewModel.open(worktree: worktree, in: viewModel.selectedOpenTarget)
                        }
                    },
                    onCheckout: {
                        viewModel.openCheckoutSheet(for: worktree)
                    },
                    onCopyPath: {
                        viewModel.copyPath(worktree)
                    },
                    onCopyBranch: {
                        viewModel.copyBranch(worktree)
                    },
                    onDelete: {
                        worktreePendingDeletion = worktree
                    },
                    onGrantAccess: {
                        viewModel.grantAccessForWorktree(worktree)
                    },
                    onOpenInEditor: { editor in
                        Task {
                            await viewModel.open(worktree: worktree, in: editor)
                        }
                    }
                )
            }
            .width(min: 220, ideal: 250)
        }
        .contextMenu(forSelectionType: String.self) { selected in
            let paths = selected.isEmpty ? viewModel.selectedWorktreePaths : selected
            if paths.count == 1, let path = paths.first, let worktree = worktreeForPath(path) {
                Section("Git") {
                    Button("Fetch", systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await viewModel.fetch(worktree: worktree)
                        }
                    }
                    Button("Pull", systemImage: "arrow.down.circle") {
                        Task {
                            await viewModel.pull(worktree: worktree)
                        }
                    }
                    Button("Checkout…", systemImage: "arrow.triangle.branch") {
                        viewModel.openCheckoutSheet(for: worktree)
                    }
                }

                Section("Open") {
                    Button("Open in \(viewModel.selectedOpenTarget.rawValue)") {
                        Task {
                            await viewModel.open(worktree: worktree, in: viewModel.selectedOpenTarget)
                        }
                    }

                    Menu("Open In…") {
                        ForEach(ExternalEditor.allCases) { editor in
                            Button(editor.rawValue) {
                                Task {
                                    await viewModel.open(worktree: worktree, in: editor)
                                }
                            }
                        }
                    }
                }

                Section("Clipboard") {
                    Button("Copy Path", systemImage: "doc.on.doc") {
                        viewModel.copyPath(worktree)
                    }
                    Button("Copy Branch", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                        viewModel.copyBranch(worktree)
                    }
                }

                Section("Advanced") {
                    Button("Grant Folder Access…", systemImage: "folder.badge.plus") {
                        viewModel.grantAccessForWorktree(worktree)
                    }
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        worktreePendingDeletion = worktree
                    }
                }
            } else if !paths.isEmpty {
                Section("Batch") {
                    Button("Fetch Selected") {
                        viewModel.selectedWorktreePaths = paths
                        Task {
                            await viewModel.fetchSelected()
                        }
                    }
                    Button("Pull Selected") {
                        viewModel.selectedWorktreePaths = paths
                        Task {
                            await viewModel.pullSelected()
                        }
                    }
                    Button("Open Selected in \(viewModel.selectedOpenTarget.rawValue)") {
                        viewModel.selectedWorktreePaths = paths
                        Task {
                            await viewModel.openSelected(in: viewModel.selectedOpenTarget)
                        }
                    }
                    Button("Copy Selected Paths") {
                        viewModel.selectedWorktreePaths = paths
                        viewModel.copySelectedPaths()
                    }
                    Button("Copy Selected Branches") {
                        viewModel.selectedWorktreePaths = paths
                        viewModel.copySelectedBranches()
                    }
                    Button("Delete Selected…", role: .destructive) {
                        viewModel.selectedWorktreePaths = paths
                        showingSelectionDeleteDialog = true
                    }
                }
            } else {
                Button("No Worktree Selected") {}
                    .disabled(true)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var deleteSelectionButtonTitle: String {
        let count = viewModel.selectedWorktreeCount
        if count == 1 {
            return "Delete Selected Worktree"
        }
        return "Delete \(count) Selected Worktrees"
    }

    private func worktreeForPath(_ path: String) -> WorktreeInfo? {
        viewModel.worktrees.first(where: { $0.path == path })
    }
}

private struct RepositoryRow: View {
    let repository: RepositoryRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repository.isFavorite ? "star.fill" : "clock")
                .foregroundStyle(repository.isFavorite ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .lineLimit(1)
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct BranchCell: View {
    let worktree: WorktreeInfo

    var body: some View {
        HStack(spacing: 6) {
            Text(worktree.branchName)
                .lineLimit(1)

            if worktree.isDetached {
                Image(systemName: "arrow.branch")
                    .foregroundStyle(.orange)
                    .help("Detached HEAD")
            }
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(worktree.lockReason ?? "Locked")
            }
            if worktree.isPrunable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(worktree.prunableReason ?? "Prunable")
            }
        }
    }
}

private struct StatusCell: View {
    let status: WorktreeStatus?

    var body: some View {
        if let status {
            Text(status.summary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(status.isDirty ? .orange : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        } else {
            Text("Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorktreeActionsCell: View {
    let worktree: WorktreeInfo
    let selectedOpenTarget: ExternalEditor
    let onFetch: () -> Void
    let onPull: () -> Void
    let onOpen: () -> Void
    let onCheckout: () -> Void
    let onCopyPath: () -> Void
    let onCopyBranch: () -> Void
    let onDelete: () -> Void
    let onGrantAccess: () -> Void
    let onOpenInEditor: (ExternalEditor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Open", action: onOpen)
                .buttonStyle(.borderedProminent)
                .help("Open in \(selectedOpenTarget.rawValue)")

            Menu {
                Section("Git") {
                    Button("Fetch", systemImage: "arrow.triangle.2.circlepath", action: onFetch)
                    Button("Pull", systemImage: "arrow.down.circle", action: onPull)
                    Button("Checkout…", systemImage: "arrow.triangle.branch", action: onCheckout)
                }

                Section("Clipboard") {
                    Button("Copy Path", systemImage: "doc.on.doc", action: onCopyPath)
                    Button("Copy Branch", systemImage: "point.topleft.down.curvedto.point.bottomright.up", action: onCopyBranch)
                }

                Menu("Open In…") {
                    ForEach(ExternalEditor.allCases) { editor in
                        Button(editor.rawValue) {
                            onOpenInEditor(editor)
                        }
                    }
                }

                Section("Advanced") {
                    Button("Grant Folder Access…", systemImage: "folder.badge.plus", action: onGrantAccess)
                    Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
        }
    }
}

private struct CreateWorktreeSheet: View {
    @Bindable var viewModel: WorktreeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Worktree")
                        .font(.title3)
                    Text("Pick source, destination, and create.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let createErrorMessage = viewModel.createErrorMessage {
                Label(createErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section("1. Source") {
                    Picker("Mode", selection: $viewModel.createRequest.mode) {
                        ForEach(CreateMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.createRequest.mode == .existingBranch {
                        TextField("Branch", text: $viewModel.createRequest.branchOrReference)
                        SuggestionStrip(
                            suggestions: viewModel.filteredCreateBranchSuggestions,
                            onSelect: { viewModel.applyCreateBranchSuggestion($0) }
                        )
                    }

                    if viewModel.createRequest.mode == .newBranch {
                        TextField("New branch", text: $viewModel.createRequest.branchOrReference)
                        TextField("Start point", text: $viewModel.createRequest.startPoint)
                        SuggestionStrip(
                            suggestions: viewModel.filteredCreateStartPointSuggestions,
                            onSelect: { viewModel.applyCreateStartPointSuggestion($0) }
                        )
                    }

                    if viewModel.createRequest.mode == .detached {
                        TextField("Start point", text: $viewModel.createRequest.startPoint)
                        SuggestionStrip(
                            suggestions: viewModel.filteredCreateStartPointSuggestions,
                            onSelect: { viewModel.applyCreateStartPointSuggestion($0) }
                        )
                    }

                    if viewModel.createSuggestionsLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading branches and references…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("2. Destination") {
                    TextField("Worktree name", text: $viewModel.createRequest.worktreeName)

                    LabeledContent("Destination folder") {
                        HStack(spacing: 8) {
                            Text(viewModel.createRequest.destinationFolderPath.isEmpty ? "No folder selected" : viewModel.createRequest.destinationFolderPath)
                                .foregroundStyle(viewModel.createRequest.destinationFolderPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Choose…") {
                                viewModel.chooseCreateDestinationFolder()
                            }
                        }
                    }
                }

                Section("3. Preview") {
                    Text(viewModel.createDestinationPreview)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isCreatingWorktree)
            .onChange(of: viewModel.createRequest.mode) { _, _ in
                viewModel.clearCreateError()
                if viewModel.createRequest.worktreeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.autofillCreateDefaults()
                }
            }
            .onChange(of: viewModel.createRequest.branchOrReference) { _, _ in
                viewModel.clearCreateError()
                if viewModel.createRequest.worktreeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.autofillCreateDefaults()
                }
            }
            .onChange(of: viewModel.createRequest.startPoint) { _, _ in
                viewModel.clearCreateError()
            }
            .onChange(of: viewModel.createRequest.worktreeName) { _, _ in
                viewModel.clearCreateError()
            }
            .onChange(of: viewModel.createRequest.destinationFolderPath) { _, _ in
                viewModel.clearCreateError()
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.showingCreateSheet = false
                }
                .disabled(viewModel.isCreatingWorktree)

                Button {
                    Task {
                        await viewModel.createWorktree()
                    }
                } label: {
                    if viewModel.isCreatingWorktree {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Creating…")
                        }
                        .frame(minWidth: 108)
                    } else {
                        Text("Create")
                            .frame(minWidth: 108)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCreateWorktree || viewModel.isCreatingWorktree)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 460)
    }
}

private struct SuggestionStrip: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(suggestions.prefix(8)), id: \.self) { suggestion in
                        Button(suggestion) {
                            onSelect(suggestion)
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct CheckoutSheet: View {
    @Bindable var viewModel: WorktreeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Checkout Branch")
                .font(.title3)

            Form {
                TextField("Branch name", text: $viewModel.checkoutBranchName)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showingCheckoutSheet = false
                }
                Button("Checkout") {
                    Task {
                        await viewModel.checkout()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 180)
    }
}
