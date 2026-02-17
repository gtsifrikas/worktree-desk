# WorktreeDesk

Native macOS SwiftUI app for managing Git worktrees.

## Features
- Repository picker with security-scoped bookmarks.
- Worktree discovery via `git worktree list --porcelain`.
- Worktree list with branch, folder, status, search/filter/sort.
- Quick actions: fetch, pull, checkout, copy path, copy branch.
- Create/delete/prune worktrees.
- Open worktree folder in Cursor, Xcode, Claude, Codex, or Finder.
- Recent repos + favorites.
- Menu bar mode (`MenuBarExtra`) with quick open + refresh.

## Download
The latest app build is published automatically on every push to `main`:

- GitHub Releases: <https://github.com/gtsifrikas/worktree-desk/releases>
- Asset: `WorktreeDesk-macOS.zip`

Release artifacts are built in CI, code-signed, notarized, and stapled when signing secrets are configured.

## Run locally
```bash
swift run WorktreeDesk
```

## Distribution notes
- Security-scoped bookmarks are used for selected repositories.
- Additional bookmarks can be granted for worktree folders outside the original repo path.
- Command execution avoids shell string interpolation (arguments are passed directly) so paths with spaces/special characters are handled safely.
- GitHub release pipeline: `.github/workflows/release.yml`.
