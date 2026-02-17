# WorktreeDesk

Native macOS SwiftUI app for managing Git worktrees.

## Current MVP features
- Repository picker with security-scoped bookmarks.
- Worktree discovery via `git worktree list --porcelain`.
- Worktree list with branch, folder, status, search/filter/sort.
- Quick actions: fetch, pull, checkout, copy path, copy branch.
- Create/delete/prune worktrees.
- Open worktree folder in Cursor, Xcode, Claude, Codex, or Finder.
- Recent repos + favorites.
- Menu bar mode (`MenuBarExtra`) with quick open + refresh.

## Run
```bash
swift run WorktreeDesk
```

## Notes on sandboxed distribution
- Security-scoped bookmarks are used for selected repositories.
- Additional bookmarks can be granted for worktree folders outside the original repo path.
- Command execution avoids shell string interpolation (arguments are passed directly) so paths with spaces/special characters are handled safely.
- For App Store/notarized distribution, enable App Sandbox in the Xcode app target and keep bookmark persistence.
