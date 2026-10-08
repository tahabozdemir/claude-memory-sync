# Contributing

Thanks for helping out. Bug reports, fixes and small improvements are all welcome. For a larger change, open an issue first so we can agree on the approach before you spend time on it.

## Setup

You need `bash`, `git`, `jq` and [ShellCheck](https://www.shellcheck.net/) (`brew install shellcheck` or `sudo apt install shellcheck`).

```bash
bash tests/test.sh
shellcheck bin/claude-memory-sync install.sh tests/test.sh
```

CI runs both on Linux and on macOS with the stock `/bin/bash` 3.2.

## Guidelines

- **Keep it one dependency-light script.** `bin/claude-memory-sync` should run with only `bash`, `git` and `jq`.
- **Stay compatible with bash 3.2**, the version macOS ships. That rules out `mapfile`, associative arrays, `${var,,}` and other bash 4+ features.
- **Hooks must never break a Claude Code session.** Anything reachable from `cmd_hook` exits 0, never prompts, and stays quiet unless Claude needs to know something.
- **Never lose a memory.** A sync must not overwrite, discard or leave a half-merged repo. When in doubt, keep both versions.
- **Add a test** in `tests/test.sh` for every behavior change. The tests simulate two machines sharing one remote; follow the existing numbered sections.
- **Update both READMEs.** `README.md` and `README.tr.md` describe the same thing; keep them in step.
- **Note user-facing changes** in [CHANGELOG.md](CHANGELOG.md) under an `Unreleased` heading.

## Releasing

1. Bump `VERSION` in `bin/claude-memory-sync`.
2. Rename the `Unreleased` heading in `CHANGELOG.md` to the new version and date, and add its compare link at the bottom. CI fails if the script's version has no changelog entry.
3. Tag the commit (`git tag v0.1.2 && git push origin v0.1.2`) and create a GitHub release from the changelog entry.
