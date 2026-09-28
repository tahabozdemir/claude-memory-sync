#!/usr/bin/env bash
#
# Install or update claude-memory-sync.
#
#   curl -fsSL https://raw.githubusercontent.com/tahabozdemir/claude-memory-sync/main/install.sh | bash
#
# or, from a clone of the repository:
#
#   ./install.sh

set -euo pipefail

REPO="${CLAUDE_MEMORY_SYNC_REPO:-tahabozdemir/claude-memory-sync}"
REF="${CLAUDE_MEMORY_SYNC_REF:-main}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TARGET="$BIN_DIR/claude-memory-sync"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required."

here=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd -P || true)
tmp=$(mktemp "${TMPDIR:-/tmp}/claude-memory-sync.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if [ -n "$here" ] && [ -f "$here/bin/claude-memory-sync" ]; then
  cp "$here/bin/claude-memory-sync" "$tmp"
else
  command -v curl >/dev/null 2>&1 || die "curl is required."
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/claude-memory-sync" -o "$tmp" \
    || die "download from github.com/$REPO failed."
fi
head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash' || die "the downloaded file isn't the claude-memory-sync script."

mkdir -p "$BIN_DIR"
chmod +x "$tmp"
mv "$tmp" "$TARGET"
say "Installed $("$TARGET" version) to $TARGET"

if ! command -v jq >/dev/null 2>&1; then
  say ""
  say "jq is also required. Install it with 'brew install jq' (macOS) or 'sudo apt install jq' (Debian/Ubuntu)."
fi

# On updates, rewrite the hooks so they point at this copy.
if [ -d "${CLAUDE_MEMORY_SYNC_DIR:-$HOME/.claude-memory}/.git" ] && command -v jq >/dev/null 2>&1; then
  "$TARGET" install-hooks >/dev/null && say "Updated the Claude Code hooks."
  exit 0
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    say ""
    say "$BIN_DIR isn't on your PATH. Add it, for example:"
    say "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc   # or ~/.bashrc"
    ;;
esac

say ""
say "Next steps:"
say "  1. Create a PRIVATE repository for your memories (once):"
say "       gh repo create claude-memory --private"
say "  2. Connect this machine:"
say "       claude-memory-sync init git@github.com:<you>/claude-memory.git"
say "  3. In each project folder:"
say "       claude-memory-sync link"
