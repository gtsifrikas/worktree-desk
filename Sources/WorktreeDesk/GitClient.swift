import Foundation

actor GitClient {
    struct ReferenceCatalog: Sendable {
        var localBranches: [String]
        var references: [String]
    }

    private final class DataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else {
                return
            }
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func runOnce(_ action: () -> Void) {
            lock.lock()
            let shouldRun = !resumed
            if shouldRun {
                resumed = true
            }
            lock.unlock()

            if shouldRun {
                action()
            }
        }
    }

    private struct ParsedWorktree {
        var path: String = ""
        var head: String?
        var branchRef: String?
        var isDetached = false
        var isLocked = false
        var lockReason: String?
        var isPrunable = false
        var prunableReason: String?
    }

    struct CommandResult: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    func listWorktrees(in repositoryRoot: URL) async throws -> [WorktreeInfo] {
        let result = try await runGit(["worktree", "list", "--porcelain"], in: repositoryRoot)
        return parseWorktrees(porcelainOutput: result.stdout)
    }

    func status(forWorktreePath path: String) async throws -> WorktreeStatus {
        let worktreeURL = URL(fileURLWithPath: path)
        async let dirtyResult = runGit(["status", "--porcelain"], in: worktreeURL)
        async let branchResult = runGit(["status", "--porcelain=v2", "--branch"], in: worktreeURL)
        let (dirty, branch) = try await (dirtyResult, branchResult)
        let isDirty = !dirty.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let aheadBehind = parseAheadBehind(from: branch.stdout)

        return WorktreeStatus(
            isDirty: isDirty,
            ahead: aheadBehind.ahead,
            behind: aheadBehind.behind,
            hasUpstream: aheadBehind.hasUpstream
        )
    }

    func fetch(path: String) async throws {
        let worktreeURL = URL(fileURLWithPath: path)
        _ = try await runGit(["fetch", "--all", "--prune"], in: worktreeURL)
    }

    func pull(path: String) async throws {
        let worktreeURL = URL(fileURLWithPath: path)
        _ = try await runGit(["pull", "--ff-only"], in: worktreeURL)
    }

    func checkout(path: String, branch: String) async throws {
        let worktreeURL = URL(fileURLWithPath: path)
        _ = try await runGit(["checkout", branch], in: worktreeURL)
    }

    func createWorktree(in repositoryRoot: URL, destinationPath: String, request: CreateWorktreeRequest) async throws {
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        var arguments = ["worktree", "add"]

        switch request.mode {
        case .existingBranch:
            guard !request.branchOrReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError(message: "Branch name is required.")
            }
            arguments += [destination, request.branchOrReference]
        case .newBranch:
            guard !request.branchOrReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError(message: "New branch name is required.")
            }
            arguments += ["-b", request.branchOrReference, destination, request.startPoint]
        case .detached:
            arguments += ["--detach", destination, request.startPoint]
        }

        _ = try await runGit(arguments, in: repositoryRoot)
    }

    func removeWorktree(in repositoryRoot: URL, path: String, force: Bool) async throws {
        var arguments = ["worktree", "remove", path]
        if force {
            arguments.append("--force")
        }
        _ = try await runGit(arguments, in: repositoryRoot)
    }

    func prune(in repositoryRoot: URL) async throws {
        _ = try await runGit(["worktree", "prune"], in: repositoryRoot)
    }

    func listReferenceCatalog(in repositoryRoot: URL) async throws -> ReferenceCatalog {
        let refsResult = try await runGit(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes", "refs/tags"],
            in: repositoryRoot
        )

        let branchResult = try await runGit(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads"],
            in: repositoryRoot
        )

        let localBranches = normalizeRefs(branchResult.stdout)
        var references = normalizeRefs(refsResult.stdout)

        if !references.contains("HEAD") {
            references.insert("HEAD", at: 0)
        }

        return ReferenceCatalog(localBranches: localBranches, references: references)
    }

    private func parseAheadBehind(from statusOutput: String) -> (ahead: Int, behind: Int, hasUpstream: Bool) {
        for line in statusOutput.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("# branch.ab ") {
                let payload = line.replacingOccurrences(of: "# branch.ab ", with: "")
                let parts = payload.split(separator: " ")
                if parts.count == 2,
                   let ahead = Int(parts[0].replacingOccurrences(of: "+", with: "")),
                   let behind = Int(parts[1].replacingOccurrences(of: "-", with: "")) {
                    return (ahead, behind, true)
                }
            }
        }
        return (0, 0, false)
    }

    private func parseWorktrees(porcelainOutput: String) -> [WorktreeInfo] {
        var parsed: [ParsedWorktree] = []
        var current: ParsedWorktree?

        for rawLine in porcelainOutput.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)

            if line.isEmpty {
                if let current {
                    parsed.append(current)
                }
                current = nil
                continue
            }

            if line.hasPrefix("worktree ") {
                if let current {
                    parsed.append(current)
                }
                current = ParsedWorktree(path: String(line.dropFirst("worktree ".count)))
                continue
            }

            guard var entry = current else {
                continue
            }

            if line.hasPrefix("HEAD ") {
                entry.head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                entry.branchRef = String(line.dropFirst("branch ".count))
            } else if line == "detached" {
                entry.isDetached = true
            } else if line.hasPrefix("locked") {
                entry.isLocked = true
                let reason = line.dropFirst("locked".count).trimmingCharacters(in: CharacterSet.whitespaces)
                entry.lockReason = reason.isEmpty ? nil : reason
            } else if line.hasPrefix("prunable") {
                entry.isPrunable = true
                let reason = line.dropFirst("prunable".count).trimmingCharacters(in: CharacterSet.whitespaces)
                entry.prunableReason = reason.isEmpty ? nil : reason
            }

            current = entry
        }

        if let current {
            parsed.append(current)
        }

        return parsed.map {
            WorktreeInfo(
                path: $0.path,
                head: $0.head,
                branchRef: $0.branchRef,
                isDetached: $0.isDetached,
                isLocked: $0.isLocked,
                lockReason: $0.lockReason,
                isPrunable: $0.isPrunable,
                prunableReason: $0.prunableReason,
                status: nil
            )
        }
    }

    private func normalizeRefs(_ raw: String) -> [String] {
        var seen = Set<String>()
        var refs: [String] = []

        for line in raw.split(whereSeparator: \.isNewline) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }
            guard !value.hasSuffix("/HEAD") else {
                continue
            }
            if seen.insert(value).inserted {
                refs.append(value)
            }
        }

        refs.sort { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return refs
    }

    private func runGit(_ arguments: [String], in directory: URL) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = directory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let stdoutBuffer = DataBuffer()
            let stderrBuffer = DataBuffer()
            let resumeGate = ResumeGate()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                stdoutBuffer.append(chunk)
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                stderrBuffer.append(chunk)
            }

            process.terminationHandler = { terminated in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

                let stdoutString = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
                let stderrString = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
                let result = CommandResult(stdout: stdoutString, stderr: stderrString, exitCode: terminated.terminationStatus)

                resumeGate.runOnce {
                    if result.exitCode != 0 {
                        continuation.resume(throwing: GitCommandError(arguments: arguments, stderr: result.stderr, exitCode: result.exitCode))
                        return
                    }

                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                resumeGate.runOnce {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
