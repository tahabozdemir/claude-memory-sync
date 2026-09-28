#!/usr/bin/env bash
#
# End-to-end tests: two simulated machines (separate HOMEs) sharing one bare
# git remote. Run: bash tests/test.sh

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
BIN="$ROOT/bin/claude-memory-sync"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT

unset CLAUDE_CONFIG_DIR CLAUDE_MEMORY_SYNC_DIR CLAUDE_PROJECT_DIR GIT_SSH_COMMAND
export GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null; then ok "$desc"; else fail "$desc"; fi
}
eq()       { [ "$1" = "$2" ]; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
has_line() { grep -Fxq -- "$2" "$1"; }
slug()     { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }

# cms <machine> <cwd> <args...>
cms() {
  local m="$1" dir="$2"
  shift 2
  (cd "$dir" && HOME="$T/$m" CLAUDE_MEMORY_SYNC_HOST="host$m" "$BIN" "$@")
}

# hook <machine> <event> [cwd]
hook() {
  printf '{"cwd":"%s","hook_event_name":"x"}' "${3:-}" \
    | HOME="$T/$1" CLAUDE_MEMORY_SYNC_HOST="host$1" "$BIN" hook "$2"
}

remote_file() {
  local ref
  ref=$(git -C "$T/remote.git" for-each-ref --format='%(refname)' refs/heads | head -n1)
  [ -n "$ref" ] && git -C "$T/remote.git" cat-file -e "$ref:$1" 2>/dev/null
}

new_project() {
  mkdir -p "$2"
  HOME="$T/$1" git -C "$2" init --quiet
  git -C "$2" remote add origin https://github.com/acme/proj.git
}

hooks_count() {
  jq '[.. | .command? // empty | select(test("claude-memory-sync"))] | length' "$1"
}

for m in A B; do
  mkdir -p "$T/$m/.claude"
  printf '[init]\n\tdefaultBranch = main\n' > "$T/$m/.gitconfig"
done
HOME="$T/A" git init --quiet --bare "$T/remote.git"
printf '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other-hook"}]}]}}\n' \
  > "$T/A/.claude/settings.json"

PA="$T/A/work/proj"
PB="$T/B/code/proj-checkout"
new_project A "$PA"
new_project B "$PB"
MA="$T/A/.claude/projects/$(slug "$PA")/memory"
MB="$T/B/.claude/projects/$(slug "$PB")/memory"
mkdir -p "$MA" "$MB"
printf -- '- [Alpha](alpha.md) — alpha\n- [Beta](beta.md) — beta\n' > "$MA/MEMORY.md"
echo "alpha fact" > "$MA/alpha.md"
echo "beta from A" > "$MA/beta.md"
printf -- '- [Alpha](alpha.md) — alpha\n- [Gamma](gamma.md) — gamma\n' > "$MB/MEMORY.md"
echo "alpha fact" > "$MB/alpha.md"
echo "beta from B" > "$MB/beta.md"
echo "gamma fact" > "$MB/gamma.md"

SA="$T/A/.claude-memory"
SB="$T/B/.claude-memory"
DA="$SA/projects/proj"
DB="$SB/projects/proj"

echo "1. init on machine A"
cms A "$T/A" init "$T/remote.git" >/dev/null
check "sync repo cloned" test -d "$SA/.git"
check "MEMORY.md merges by union" grep -q '^MEMORY.md merge=union' "$SA/.gitattributes"
check "scaffold pushed" remote_file .gitattributes
check "three hooks installed" eq "$(hooks_count "$T/A/.claude/settings.json")" 3
check "Stop hook runs async" jq -e '[.hooks.Stop[].hooks[] | select(.command | test("claude-memory-sync")) | .async] == [true]' "$T/A/.claude/settings.json"
check "existing settings kept" jq -e '.theme == "dark" and ([.hooks.Stop[].hooks[].command] | index("echo other-hook") != null)' "$T/A/.claude/settings.json"
check "settings backed up" test -f "$T/A/.claude/settings.json.bak-claude-memory-sync"

echo "2. init again is idempotent"
cms A "$T/A" init >/dev/null
check "still three hooks" eq "$(hooks_count "$T/A/.claude/settings.json")" 3

echo "3. link on A"
cms A "$PA" link >/dev/null
check "autoMemoryDirectory set" jq -e '.autoMemoryDirectory == "~/.claude-memory/projects/proj"' "$PA/.claude/settings.local.json"
check "memory moved into sync repo" test -f "$DA/alpha.md"
check "memory pushed" remote_file projects/proj/beta.md
check "settings.local.json git-ignored" git -C "$PA" check-ignore -q .claude/settings.local.json
check "original folder kept as backup" test -f "$MA/alpha.md"
check "link again is a no-op" contains "$(cms A "$PA" link)" "Already linked"

echo "4. init + link on B (other path, its own memories)"
cms B "$T/B" init "$T/remote.git" >/dev/null
cms B "$PB" link >/dev/null
check "same project name from origin" jq -e '.autoMemoryDirectory == "~/.claude-memory/projects/proj"' "$PB/.claude/settings.local.json"
check "identical file not duplicated" test ! -e "$DB/alpha.conflict-hostB.md"
check "differing file: synced version kept" eq "$(cat "$DB/beta.md")" "beta from A"
check "differing file: B's version kept beside it" eq "$(cat "$DB/beta.conflict-hostB.md")" "beta from B"
check "new file added" test -f "$DB/gamma.md"
check "index has A's line" has_line "$DB/MEMORY.md" "- [Beta](beta.md) — beta"
check "index has B's line" has_line "$DB/MEMORY.md" "- [Gamma](gamma.md) — gamma"
check "index has no duplicates" eq "$(sort "$DB/MEMORY.md" | uniq -d)" ""

echo "5. session start on A pulls B's memories and tells Claude"
OUT=$(hook A session-start "$PA")
check "gamma pulled" test -f "$DA/gamma.md"
check "context says memory was updated" contains "$OUT" "updated from another machine"
check "context carries the new index" contains "$OUT" "- [Gamma](gamma.md) — gamma"
check "context lists the conflict copy" contains "$OUT" "beta.conflict-hostB.md"
check "quiet when nothing changed" eq "$(hook A session-start "$PA" | grep -c 'updated from another machine' || true)" 0

echo "6. both machines add memories at the same time"
printf -- '- [Delta](delta.md) — from A\n' >> "$DA/MEMORY.md"
echo "delta fact" > "$DA/delta.md"
printf -- '- [Eps](eps.md) — from B\n' >> "$DB/MEMORY.md"
echo "eps fact" > "$DB/eps.md"
hook A stop
hook B stop
cms A "$T/A" sync >/dev/null
for d in "$DA" "$DB"; do
  check "index has both new lines ($(basename "$(dirname "$(dirname "$(dirname "$d")")")"))" \
    eval 'has_line "$d/MEMORY.md" "- [Delta](delta.md) — from A" && has_line "$d/MEMORY.md" "- [Eps](eps.md) — from B"'
done
check "no conflict markers" eval '! grep -rq "<<<<<<<" "$DA" "$DB"'

echo "7. same memory edited on both machines"
echo "alpha A2" > "$DA/alpha.md"
echo "alpha B2" > "$DB/alpha.md"
cms A "$T/A" sync >/dev/null
cms B "$T/B" sync >/dev/null
check "remote version kept in place" eq "$(cat "$DB/alpha.md")" "alpha A2"
check "local version kept as conflict copy" eq "$(cat "$DB/alpha.conflict-hostB.md")" "alpha B2"
check "no merge left in progress" test ! -f "$SB/.git/MERGE_HEAD"
cms A "$T/A" sync >/dev/null
check "A receives the conflict copy" test -f "$DA/alpha.conflict-hostB.md"

echo "8. deleted on one machine, edited on the other"
rm "$DA/delta.md"
echo "delta edited" > "$DB/delta.md"
cms A "$T/A" sync >/dev/null
cms B "$T/B" sync >/dev/null
cms A "$T/A" sync >/dev/null
check "edit wins over delete (B)" eq "$(cat "$DB/delta.md")" "delta edited"
check "edit wins over delete (A)" eq "$(cat "$DA/delta.md" 2>/dev/null)" "delta edited"

echo "9. offline"
git -C "$SA" remote set-url origin "$T/missing.git"
echo "zeta fact" > "$DA/zeta.md"
set +e
OUT=$(hook A session-start "$PA")
RC=$?
set -e
check "hook exits 0" eq "$RC" 0
check "Claude is told memory may be stale" contains "$OUT" "Couldn't reach"
check "change committed locally" eq "$(git -C "$SA" status --porcelain)" ""
git -C "$SA" remote set-url origin "$T/remote.git"
hook A stop
check "pushed once back online" remote_file projects/proj/zeta.md

echo "10. unlinked folders"
PB2="$T/B/elsewhere/proj"
new_project B "$PB2"
check "hint when a synced project has this name" contains "$(hook B session-start "$PB2")" "claude-memory-sync link"
mkdir -p "$T/B/unrelated"
check "silent for unrelated folders" eq "$(hook B session-start "$T/B/unrelated")" ""

echo "11. status"
OUT=$(cms A "$PA" status)
check "status shows link" contains "$OUT" "linked as 'proj'"
check "status lists conflict copies" contains "$OUT" "alpha.conflict-hostB.md"

echo "12. unlink"
cms A "$PA" unlink >/dev/null
check "setting removed" jq -e 'has("autoMemoryDirectory") | not' "$PA/.claude/settings.local.json"
check "memory copied back to default folder" test -f "$MA/gamma.md"

echo "13. uninstall-hooks"
cms A "$T/A" uninstall-hooks >/dev/null
check "our hooks removed" eq "$(hooks_count "$T/A/.claude/settings.json")" 0
check "other hooks and settings kept" jq -e '.theme == "dark" and .hooks.Stop[0].hooks[0].command == "echo other-hook" and (.hooks | has("SessionStart") | not)' "$T/A/.claude/settings.json"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
