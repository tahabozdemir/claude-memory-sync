# Changelog

Notable changes to claude-memory-sync. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-09-28

### Changed

- `link` and `status` only suggest synced projects that aren't linked on this machine yet, instead of listing every synced project.

## [0.1.0] - 2026-09-28

### Added

- First release: `init`, `link`, `unlink`, `sync`, `status`, `install-hooks` and `uninstall-hooks`.
- `SessionStart`, `Stop` and `SessionEnd` hooks that pull and push auto memory automatically.
- Conflict handling that never blocks a sync: `MEMORY.md` merges by union, other files keep both versions.

[0.1.1]: https://github.com/tahabozdemir/claude-memory-sync/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tahabozdemir/claude-memory-sync/releases/tag/v0.1.0
