import Foundation
import Observation

@MainActor
@Observable
final class RepositoryStore {
    private(set) var repositories: [RepositoryRecord] = []
    var selectedRepositoryID: UUID? {
        didSet {
            save()
        }
    }

    private let repositoriesKey = "worktree.repositories"
    private let selectedRepositoryKey = "worktree.selectedRepository"
    private let extraPathBookmarksKey = "worktree.extraPathBookmarks"
    private var extraPathBookmarks: [String: Data] = [:]

    init() {
        load()
    }

    var selectedRepository: RepositoryRecord? {
        repositories.first(where: { $0.id == selectedRepositoryID })
    }

    var sortedRepositories: [RepositoryRecord] {
        repositories.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            if lhs.lastOpenedAt != rhs.lastOpenedAt {
                return lhs.lastOpenedAt > rhs.lastOpenedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func addRepository(url: URL, bookmarkData: Data) {
        let normalizedPath = url.standardizedFileURL.path
        if let index = repositories.firstIndex(where: { $0.path == normalizedPath }) {
            repositories[index].bookmarkData = bookmarkData
            repositories[index].lastOpenedAt = Date()
            selectedRepositoryID = repositories[index].id
            save()
            return
        }

        let record = RepositoryRecord(
            id: UUID(),
            name: url.lastPathComponent,
            path: normalizedPath,
            bookmarkData: bookmarkData,
            isFavorite: false,
            lastOpenedAt: Date()
        )
        repositories.append(record)
        selectedRepositoryID = record.id
        save()
    }

    func removeRepository(id: UUID) {
        repositories.removeAll(where: { $0.id == id })
        if selectedRepositoryID == id {
            selectedRepositoryID = repositories.first?.id
        }
        save()
    }

    func toggleFavorite(id: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else {
            return
        }
        repositories[index].isFavorite.toggle()
        save()
    }

    func markOpened(id: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else {
            return
        }
        repositories[index].lastOpenedAt = Date()
        save()
    }

    func addPathBookmark(for url: URL) throws {
        let normalizedPath = url.standardizedFileURL.path
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        extraPathBookmarks[normalizedPath] = bookmark
        save()
    }

    func withScopedRepositoryAccess<T>(id: UUID, _ body: (URL) async throws -> T) async throws -> T {
        guard let repository = repositories.first(where: { $0.id == id }) else {
            throw AppError(message: "No repository selected.")
        }

        let url = try resolveRepositoryURL(repository)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let result = try await body(url)
        markOpened(id: id)
        return result
    }

    func withScopedPathAccess<T>(path: String, _ body: (URL) async throws -> T) async throws -> T {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let url = URL(fileURLWithPath: normalizedPath)
        let directAccess = url.startAccessingSecurityScopedResource()
        if directAccess {
            defer { url.stopAccessingSecurityScopedResource() }
            return try await body(url)
        }

        guard let entry = bookmarkEntry(forPath: normalizedPath) else {
            return try await body(url)
        }

        do {
            var isStale = false
            let resolved = try URL(
                resolvingBookmarkData: entry.data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try addPathBookmark(for: resolved)
            }

            let didAccess = resolved.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    resolved.stopAccessingSecurityScopedResource()
                }
            }

            return try await body(resolved)
        } catch {
            // Corrupt/migrated bookmark data should not block normal filesystem access.
            extraPathBookmarks.removeValue(forKey: entry.key)
            save()
            return try await body(url)
        }
    }

    private func bookmarkEntry(forPath normalizedPath: String) -> (key: String, data: Data)? {
        if let exact = extraPathBookmarks[normalizedPath] {
            return (normalizedPath, exact)
        }

        let sortedKeys = extraPathBookmarks.keys.sorted { lhs, rhs in
            lhs.count > rhs.count
        }

        for key in sortedKeys where normalizedPath == key || normalizedPath.hasPrefix(key + "/") {
            if let data = extraPathBookmarks[key] {
                return (key, data)
            }
        }

        return nil
    }

    private func resolveRepositoryURL(_ repository: RepositoryRecord) throws -> URL {
        let fallbackURL = URL(fileURLWithPath: repository.path).standardizedFileURL

        do {
            var isStale = false
            let resolved = try URL(
                resolvingBookmarkData: repository.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let refreshed = try resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                    repositories[index].bookmarkData = refreshed
                    save()
                }
            }

            return resolved.standardizedFileURL
        } catch {
            guard FileManager.default.fileExists(atPath: fallbackURL.path) else {
                throw AppError(message: "Cannot access repository at \(repository.path). Re-add the repository folder.")
            }

            if let refreshed = try? fallbackURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
               let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                repositories[index].bookmarkData = refreshed
                save()
            }

            return fallbackURL
        }
    }

    private func load() {
        let defaults = UserDefaults.standard

        if let repositoriesData = defaults.data(forKey: repositoriesKey),
           let decoded = try? JSONDecoder().decode([RepositoryRecord].self, from: repositoriesData) {
            repositories = decoded
        }

        if let selected = defaults.string(forKey: selectedRepositoryKey) {
            selectedRepositoryID = UUID(uuidString: selected)
        }

        if let bookmarksData = defaults.data(forKey: extraPathBookmarksKey),
           let decodedBookmarks = try? JSONDecoder().decode([String: Data].self, from: bookmarksData) {
            extraPathBookmarks = decodedBookmarks
        }

        if selectedRepositoryID == nil {
            selectedRepositoryID = repositories.first?.id
        }
    }

    private func save() {
        let defaults = UserDefaults.standard

        if let repositoriesData = try? JSONEncoder().encode(repositories) {
            defaults.set(repositoriesData, forKey: repositoriesKey)
        }

        if let selectedRepositoryID {
            defaults.set(selectedRepositoryID.uuidString, forKey: selectedRepositoryKey)
        } else {
            defaults.removeObject(forKey: selectedRepositoryKey)
        }

        if let bookmarksData = try? JSONEncoder().encode(extraPathBookmarks) {
            defaults.set(bookmarksData, forKey: extraPathBookmarksKey)
        }
    }
}
