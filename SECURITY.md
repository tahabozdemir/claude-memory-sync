# Security policy

claude-memory-sync moves Claude Code's auto memory, which can hold private details about your work, between your machines and a git remote. Issues that could expose that memory or let someone else change it are taken seriously.

## Supported versions

Only the latest release gets fixes. Update with the [install command](README.md#2-install-on-every-machine).

## Reporting a vulnerability

Please **don't open a public issue.** Report it privately through [GitHub's vulnerability reporting](https://github.com/tahabozdemir/claude-memory-sync/security/advisories/new) instead, with steps to reproduce and the output of `claude-memory-sync version`.

You'll get a reply within a week. Once a fix is released, the advisory is published with credit to you unless you'd rather stay anonymous.

## In scope

- Memory content leaking anywhere other than the sync repository you configured
- Code execution through crafted memory files, project names, git remotes or Claude Code hook input
- The installer fetching or running something other than this project's script
- `init` accepting a public GitHub repository without `--allow-public`

The privacy of the sync repository itself is your responsibility: keep it private.
