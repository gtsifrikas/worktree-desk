import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WorktreeViewModel {
    var searchText: String = ""
    var sortMode: WorktreeSortMode = .path
    var worktrees: [WorktreeInfo] = []
    var isLoading = false
    var selectedWorktreePaths: Set<String> = []
    var selectedOpenTarget: ExternalEditor = .cursor
    var errorMessage: String?

    var showingCreateSheet = false
    var createRequest = CreateWorktreeRequest()
    var createErrorMessage: String?
    var createSuggestionsLoading = false
    var isCreatingWorktree = false
    var createBranchSuggestions: [String] = []
    var createStartPointSuggestions: [String] = []

    var showingCheckoutSheet = false
    var checkoutBranchName = ""
    var checkoutWorktreePath: String?

    private let repositoryStore: RepositoryStore
    private let gitClient = GitClient()

    init(repositoryStore: RepositoryStore) {
        self.repositoryStore = repositoryStore
    }

    var repositories: [RepositoryRecord] {
        repositoryStore.sortedRepositories
    }

    var selectedRepository: RepositoryRecord? {
        repositoryStore.selectedRepository
    }

    var selectedRepositoryID: UUID? {
        repositoryStore.selectedRepositoryID
    }

    var filteredWorktrees: [WorktreeInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = worktrees.filter { item in
            guard !query.isEmpty else {
                return true
            }
            return item.path.lowercased().contains(query)
                || item.folderName.lowercased().contains(query)
                || item.branchName.lowercased().contains(query)
        }

        return filtered.sorted(by: sortComparator)
    }

    var selectedWorktreeCount: Int {
        selectedWorktreePaths.count
    }

    var hasSelection: Bool {
        !selectedWorktreePaths.isEmpty
    }

    var hasSingleSelection: Bool {
        selectedWorktreePaths.count == 1
    }

    var selectedWorktrees: [WorktreeInfo] {
        worktrees
            .filter { selectedWorktreePaths.contains($0.path) }
            .sorted(by: sortComparator)
    }

    var selectedSingleWorktree: WorktreeInfo? {
        guard hasSingleSelection else {
            return nil
        }
        return selectedWorktrees.first
    }

    func setSelectedRepository(id: UUID?) {
        selectedWorktreePaths.removeAll()
        repositoryStore.selectedRepositoryID = id
        Task {
            await refreshWorktrees()
        }
    }

    func pickRepositoryFolder(activateApp: Bool = false) {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        }

        let panel = NSOpenPanel()
        panel.title = "Select Git Repository"
        panel.prompt = "Use Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            repositoryStore.addRepository(url: url, bookmarkData: bookmark)
            Task {
                await refreshWorktrees()
            }
        } catch {
            present(error)
        }
    }

    func removeSelectedRepository() {
        guard let id = repositoryStore.selectedRepositoryID else {
            return
        }
        selectedWorktreePaths.removeAll()
        repositoryStore.removeRepository(id: id)
        Task {
            await refreshWorktrees()
        }
    }

    func toggleFavoriteSelectedRepository() {
        guard let id = repositoryStore.selectedRepositoryID else {
            return
        }
        repositoryStore.toggleFavorite(id: id)
    }

    func toggleFavorite(repositoryID: UUID) {
        repositoryStore.toggleFavorite(id: repositoryID)
    }

    func removeRepository(id: UUID) {
        selectedWorktreePaths.removeAll()
        repositoryStore.removeRepository(id: id)
        Task {
            await refreshWorktrees()
        }
    }

    func refreshWorktrees() async {
        guard let repository = repositoryStore.selectedRepository else {
            worktrees = []
            selectedWorktreePaths.removeAll()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let base = try await repositoryStore.withScopedRepositoryAccess(id: repository.id) { repoURL in
                try await gitClient.listWorktrees(in: repoURL)
            }

            var enriched: [WorktreeInfo] = []
            for var worktree in base {
                do {
                    worktree.status = try await repositoryStore.withScopedPathAccess(path: worktree.path) { pathURL in
                        try await gitClient.status(forWorktreePath: pathURL.path)
                    }
                } catch {
                    worktree.status = nil
                }
                enriched.append(worktree)
            }

            worktrees = enriched
            let availablePaths = Set(enriched.map(\.path))
            selectedWorktreePaths.formIntersection(availablePaths)
        } catch {
            present(error)
        }
    }

    func openCreateWorktreeSheet() {
        createRequest = CreateWorktreeRequest()
        createErrorMessage = nil
        isCreatingWorktree = false
        createBranchSuggestions = []
        createStartPointSuggestions = []
        autofillCreateDefaults()
        showingCreateSheet = true
        Task {
            await loadCreateSuggestionCatalog()
        }
    }

    func createWorktree() async {
        guard let repository = repositoryStore.selectedRepository else {
            return
        }
        guard !isCreatingWorktree else {
            return
        }

        isCreatingWorktree = true
        defer { isCreatingWorktree = false }
        do {
            createErrorMessage = nil
            let request = createRequest
            let destinationPath = try buildDestinationPath(
                destinationFolderPath: request.destinationFolderPath,
                worktreeName: request.worktreeName
            )

            let destinationFolderURL = URL(fileURLWithPath: request.destinationFolderPath).standardizedFileURL
            try? repositoryStore.addPathBookmark(for: destinationFolderURL)

            try await repositoryStore.withScopedPathAccess(path: destinationFolderURL.path) { _ in
                try await repositoryStore.withScopedRepositoryAccess(id: repository.id) { repoURL in
                    try await gitClient.createWorktree(in: repoURL, destinationPath: destinationPath, request: request)
                }
            }

            try? repositoryStore.addPathBookmark(for: URL(fileURLWithPath: destinationPath))
            showingCreateSheet = false
            createErrorMessage = nil
            await refreshWorktrees()
        } catch {
            createErrorMessage = localizedMessage(for: error)
        }
    }

    var createDestinationPreview: String {
        let folder = createRequest.destinationFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = createRequest.worktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty, !name.isEmpty else {
            return "Choose a folder and enter a worktree name."
        }
        return URL(fileURLWithPath: folder).appendingPathComponent(name).standardizedFileURL.path
    }

    var canCreateWorktree: Bool {
        let name = createRequest.worktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = createRequest.destinationFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folder.isEmpty else {
            return false
        }

        switch createRequest.mode {
        case .existingBranch:
            return !createRequest.branchOrReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .newBranch:
            return !createRequest.branchOrReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !createRequest.startPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .detached:
            return !createRequest.startPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func clearCreateError() {
        createErrorMessage = nil
    }

    func chooseCreateDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Destination Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if !createRequest.destinationFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: createRequest.destinationFolderPath)
        } else if let repository = repositoryStore.selectedRepository {
            panel.directoryURL = URL(fileURLWithPath: repository.path).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        createRequest.destinationFolderPath = url.standardizedFileURL.path
        do {
            try repositoryStore.addPathBookmark(for: url)
        } catch {
            present(error)
        }
    }

    func autofillCreateDefaults() {
        if createRequest.destinationFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let repository = repositoryStore.selectedRepository {
            createRequest.destinationFolderPath = URL(fileURLWithPath: repository.path)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path
        }

        if createRequest.worktreeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createRequest.worktreeName = suggestedWorktreeName()
        }
    }

    var filteredCreateBranchSuggestions: [String] {
        autocompleteSuggestions(
            query: createRequest.branchOrReference,
            source: createBranchSuggestions,
            limit: 10
        )
    }

    var filteredCreateStartPointSuggestions: [String] {
        autocompleteSuggestions(
            query: createRequest.startPoint,
            source: createStartPointSuggestions,
            limit: 10
        )
    }

    func applyCreateBranchSuggestion(_ suggestion: String) {
        createRequest.branchOrReference = suggestion
    }

    func applyCreateStartPointSuggestion(_ suggestion: String) {
        createRequest.startPoint = suggestion
    }

    func delete(worktree: WorktreeInfo, force: Bool) async {
        await delete(paths: [worktree.path], force: force)
    }

    func deleteSelected(force: Bool) async {
        await delete(paths: Array(selectedWorktreePaths), force: force)
    }

    func prune() async {
        guard let repository = repositoryStore.selectedRepository else {
            return
        }

        do {
            try await repositoryStore.withScopedRepositoryAccess(id: repository.id) { repoURL in
                try await gitClient.prune(in: repoURL)
            }
            await refreshWorktrees()
        } catch {
            present(error)
        }
    }

    func fetch(worktree: WorktreeInfo) async {
        do {
            try await withScopedWorktreePath(worktree.path) { path in
                try await self.gitClient.fetch(path: path)
            }
            await refreshWorktrees()
        } catch {
            present(error)
        }
    }

    func pull(worktree: WorktreeInfo) async {
        do {
            try await withScopedWorktreePath(worktree.path) { path in
                try await self.gitClient.pull(path: path)
            }
            await refreshWorktrees()
        } catch {
            present(error)
        }
    }

    func fetchSelected() async {
        await performBatchAction(name: "Fetch") { path in
            try await self.gitClient.fetch(path: path)
        }
        await refreshWorktrees()
    }

    func pullSelected() async {
        await performBatchAction(name: "Pull") { path in
            try await self.gitClient.pull(path: path)
        }
        await refreshWorktrees()
    }

    func openCheckoutSheet(for worktree: WorktreeInfo) {
        checkoutWorktreePath = worktree.path
        checkoutBranchName = ""
        showingCheckoutSheet = true
    }

    func openCheckoutSheetForSelection() {
        guard let worktree = selectedSingleWorktree else {
            present(AppError(message: "Select exactly one worktree to checkout."))
            return
        }
        openCheckoutSheet(for: worktree)
    }

    func checkout() async {
        guard let checkoutWorktreePath else {
            return
        }

        let branch = checkoutBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            present(AppError(message: "Branch name is required."))
            return
        }

        do {
            try await withScopedWorktreePath(checkoutWorktreePath) { path in
                try await self.gitClient.checkout(path: path, branch: branch)
            }

            showingCheckoutSheet = false
            await refreshWorktrees()
        } catch {
            present(error)
        }
    }

    func copyPath(_ worktree: WorktreeInfo) {
        copyToPasteboard(worktree.path)
    }

    func copyBranch(_ worktree: WorktreeInfo) {
        copyToPasteboard(worktree.branchName)
    }

    func copySelectedPaths() {
        let paths = selectedWorktrees.map(\.path)
        guard !paths.isEmpty else {
            return
        }
        copyToPasteboard(paths.joined(separator: "\n"))
    }

    func copySelectedBranches() {
        var seen = Set<String>()
        let branches = selectedWorktrees
            .map(\.branchName)
            .filter { seen.insert($0).inserted }
        guard !branches.isEmpty else {
            return
        }
        copyToPasteboard(branches.joined(separator: "\n"))
    }

    func open(worktree: WorktreeInfo, in editor: ExternalEditor) async {
        let url = URL(fileURLWithPath: worktree.path)

        if editor == .finder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        if editor == .warp {
            do {
                try Self.openInWarp(path: url.path)
            } catch {
                present(error)
            }
            return
        }

        do {
            try await Self.openInApplication(editor.rawValue, path: url.path)
        } catch {
            present(error)
        }
    }

    func openSelected(in editor: ExternalEditor) async {
        let targets = selectedWorktrees
        guard !targets.isEmpty else {
            return
        }

        for worktree in targets {
            await open(worktree: worktree, in: editor)
        }
    }

    func grantAccessForWorktree(_ worktree: WorktreeInfo) {
        let panel = NSOpenPanel()
        panel.title = "Grant Access"
        panel.prompt = "Grant"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: worktree.path).deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try repositoryStore.addPathBookmark(for: url)
            Task {
                await refreshWorktrees()
            }
        } catch {
            present(error)
        }
    }

    private func delete(paths: [String], force: Bool) async {
        guard let repository = repositoryStore.selectedRepository else {
            return
        }

        let targetPaths = Array(Set(paths))
        guard !targetPaths.isEmpty else {
            return
        }

        var failures: [String] = []

        do {
            try await repositoryStore.withScopedRepositoryAccess(id: repository.id) { repoURL in
                for path in targetPaths {
                    if path == repository.path {
                        failures.append("\(URL(fileURLWithPath: path).lastPathComponent): cannot remove the main repository worktree")
                        continue
                    }

                    do {
                        try await self.gitClient.removeWorktree(in: repoURL, path: path, force: force)
                    } catch {
                        let label = URL(fileURLWithPath: path).lastPathComponent
                        failures.append("\(label): \(self.localizedMessage(for: error))")
                    }
                }
            }

            await refreshWorktrees()

            if !failures.isEmpty {
                present(AppError(message: failureSummary(action: "Delete", failures: failures)))
            }
        } catch {
            present(error)
        }
    }

    private func performBatchAction(
        name: String,
        action: @escaping (String) async throws -> Void
    ) async {
        let targets = selectedWorktrees
        guard !targets.isEmpty else {
            return
        }

        var failures: [String] = []

        for worktree in targets {
            do {
                try await withScopedWorktreePath(worktree.path) { path in
                    try await action(path)
                }
            } catch {
                failures.append("\(worktree.folderName): \(localizedMessage(for: error))")
            }
        }

        if !failures.isEmpty {
            present(AppError(message: failureSummary(action: name, failures: failures)))
        }
    }

    private func withScopedWorktreePath(
        _ path: String,
        action: @escaping (String) async throws -> Void
    ) async throws {
        try await repositoryStore.withScopedPathAccess(path: path) { url in
            try await action(url.path)
        }
    }

    private func failureSummary(action: String, failures: [String]) -> String {
        let head = failures.prefix(3).joined(separator: "\n")
        let extraCount = failures.count - min(failures.count, 3)
        let extra = extraCount > 0 ? "\n...and \(extraCount) more." : ""
        return "\(action) failed for \(failures.count) worktree(s):\n\(head)\(extra)"
    }

    private func buildDestinationPath(
        destinationFolderPath: String,
        worktreeName: String
    ) throws -> String {
        let folder = destinationFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty else {
            throw AppError(message: "Destination folder is required.")
        }

        let name = worktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError(message: "Worktree name is required.")
        }

        return URL(fileURLWithPath: folder).appendingPathComponent(name).standardizedFileURL.path
    }

    private func suggestedWorktreeName() -> String {
        let rawSource: String
        switch createRequest.mode {
        case .existingBranch, .newBranch:
            rawSource = createRequest.branchOrReference
        case .detached:
            rawSource = "detached-head"
        }

        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty {
            return "worktree"
        }
        return sanitizeWorktreeName(source)
    }

    private func sanitizeWorktreeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let lowered = value.lowercased()
        let pieces = lowered.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let joined = pieces.joined()
        let collapsed = joined.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "worktree" : trimmed
    }

    private func loadCreateSuggestionCatalog() async {
        guard let repository = repositoryStore.selectedRepository else {
            return
        }

        createSuggestionsLoading = true
        defer { createSuggestionsLoading = false }

        do {
            let catalog = try await repositoryStore.withScopedRepositoryAccess(id: repository.id) { repoURL in
                try await gitClient.listReferenceCatalog(in: repoURL)
            }

            createBranchSuggestions = catalog.localBranches
            createStartPointSuggestions = catalog.references
        } catch {
            createBranchSuggestions = []
            createStartPointSuggestions = []
        }
    }

    private func autocompleteSuggestions(query: String, source: [String], limit: Int) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let lowercasedQuery = trimmed.lowercased()

        let prefixMatches = source.filter { $0.lowercased().hasPrefix(lowercasedQuery) }
        let containsMatches = source.filter {
            !$0.lowercased().hasPrefix(lowercasedQuery) && $0.lowercased().contains(lowercasedQuery)
        }

        return Array((prefixMatches + containsMatches).prefix(limit))
    }

    private func sortComparator(lhs: WorktreeInfo, rhs: WorktreeInfo) -> Bool {
        switch sortMode {
        case .path:
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        case .branch:
            return lhs.branchName.localizedCaseInsensitiveCompare(rhs.branchName) == .orderedAscending
        case .status:
            let lhsDirty = lhs.status?.isDirty == true
            let rhsDirty = rhs.status?.isDirty == true
            if lhsDirty != rhsDirty {
                return lhsDirty && !rhsDirty
            }
            let lhsDelta = (lhs.status?.ahead ?? 0) + (lhs.status?.behind ?? 0)
            let rhsDelta = (rhs.status?.ahead ?? 0) + (rhs.status?.behind ?? 0)
            if lhsDelta != rhsDelta {
                return lhsDelta > rhsDelta
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func present(_ error: Error) {
        errorMessage = localizedMessage(for: error)
    }

    nonisolated private static func openInWarp(path: String) throws {
        let warpBundleIDs = ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"]
        let isWarpRunning = warpBundleIDs.contains { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        let action = isWarpRunning ? "new_tab" : "new_window"

        guard let url = URL(string: "warp://action/\(action)?path=\(encodedPath)") else {
            throw AppError(message: "Unable to create Warp URL.")
        }

        guard NSWorkspace.shared.open(url) else {
            throw AppError(message: "Failed to open Warp.")
        }
    }

    nonisolated private static func openInApplication(_ application: String, path: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", application, path]

            process.terminationHandler = { terminated in
                if terminated.terminationStatus == 0 {
                    continuation.resume()
                    return
                }
                continuation.resume(throwing: AppError(message: "Failed to open \(application)."))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
