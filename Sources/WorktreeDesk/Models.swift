import Foundation

enum WorktreeSortMode: String, CaseIterable, Identifiable, Sendable {
    case path = "Path"
    case branch = "Branch"
    case status = "Status"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .path:
            return "Path (A-Z)"
        case .branch:
            return "Branch (A-Z)"
        case .status:
            return "Status (dirty first)"
        }
    }

    var shortTitle: String {
        switch self {
        case .path:
            return "Path"
        case .branch:
            return "Branch"
        case .status:
            return "Status"
        }
    }
}

enum ExternalEditor: String, CaseIterable, Identifiable, Codable, Sendable {
    case cursor = "Cursor"
    case xcode = "Xcode"
    case claude = "Claude"
    case codex = "Codex"
    case finder = "Finder"

    var id: String { rawValue }
}

enum CreateMode: String, CaseIterable, Identifiable, Sendable {
    case existingBranch = "Existing Branch"
    case newBranch = "New Branch"
    case detached = "Detached"

    var id: String { rawValue }
}

struct CreateWorktreeRequest: Sendable {
    var mode: CreateMode = .existingBranch
    var destinationPath: String = ""
    var branchOrReference: String = ""
    var startPoint: String = "HEAD"
}

struct RepositoryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var path: String
    var bookmarkData: Data
    var isFavorite: Bool
    var lastOpenedAt: Date
}

struct WorktreeStatus: Hashable, Sendable {
    var isDirty: Bool
    var ahead: Int
    var behind: Int
    var hasUpstream: Bool

    var summary: String {
        var components: [String] = []
        if isDirty {
            components.append("dirty")
        }
        if hasUpstream {
            if ahead > 0 {
                components.append("↑\(ahead)")
            }
            if behind > 0 {
                components.append("↓\(behind)")
            }
            if ahead == 0 && behind == 0 {
                components.append("up-to-date")
            }
        }
        if components.isEmpty {
            return "clean"
        }
        return components.joined(separator: " ")
    }
}

struct WorktreeInfo: Identifiable, Hashable, Sendable {
    var id: String { path }

    var path: String
    var head: String?
    var branchRef: String?
    var isDetached: Bool
    var isLocked: Bool
    var lockReason: String?
    var isPrunable: Bool
    var prunableReason: String?
    var status: WorktreeStatus?

    var folderName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var branchName: String {
        if let branchRef {
            return branchRef.replacingOccurrences(of: "refs/heads/", with: "")
        }
        return isDetached ? "DETACHED" : "(unknown)"
    }
}

struct GitCommandError: LocalizedError, Sendable {
    var arguments: [String]
    var stderr: String
    var exitCode: Int32

    var errorDescription: String? {
        let joined = arguments.joined(separator: " ")
        let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? "git \(joined) failed with code \(exitCode)." : details
    }
}

struct AppError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
