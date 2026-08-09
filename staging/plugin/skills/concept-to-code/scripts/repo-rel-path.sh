#!/bin/bash
# repo-rel-path.sh v1.0 — print a path's repo-relative form, or the path unchanged when it does
# not belong to the given checkout. Extracted verbatim from `concept-to-code` Step 5.0.1's inline
# `rel()` (issue #385, ADR-0132 §D2).
#
# WHY THIS IS A FILE AND NOT A FENCE. A skill's markdown body is RENDERED before the model sees
# it, and Claude Code whitespace-splits the skill's own invocation arguments and substitutes them
# into every positional-parameter token in that body — bash fences included, because a fence is
# just text. `rel()` read a positional parameter, so what the model executed was a function whose
# argument had been replaced by an unrelated word before it ever ran: syntactically valid shell
# doing the wrong thing, silently, inside the pre-flight that guards entry to every Step 5. A FILE
# is never rendered, which is the whole of the fix.
#
# ------------------------------------------------------------------------------------------------
# THE MECHANISM, copied from the fence this was extracted from. Four guards, none of them
# decorative — each is a fix for a defect measured in a real chain run. Do not "simplify" any of
# them.
#
# It ASKS GIT for the repo-relative path. It does not compare strings, and that is the whole
# point: every string form of this comparison has a normalisation it does not perform.
#
# The first draft compared `git rev-parse --show-toplevel` (resolved) against the caller's path
# (not), so it shortened nothing and EVERY artifact classified as OTHER — including the manifest,
# which made the exemption silently inert. #239 fixed that by resolving both sides with
# `cd … && pwd -P`. That closed the symlink half only: **`pwd -P` resolves symlinks, it does not
# normalise case.** APFS is case-insensitive and case-preserving, so `cd /Users/x/developer/…`
# succeeds and reports the casing you traversed, while git reports the casing it recorded — the
# prefix match failed again, on the same file, for a different reason, and the exemption was inert
# on every run from a differently-cased CWD (issue #344, found by running the chain, twice over).
#
# Deriving the prefix from git removes the comparison rather than correcting it, so there is no
# third normalisation left to miss. The `-ef` guard is device+inode identity — "is this the same
# directory" answered without going back through a string compare, which is the trap being
# removed. It is what keeps an artifact living in a DIFFERENT repository from being handed that
# repository's prefix and silently exempted.
#
# Pinned by `recovery-preflight.test.sh`: RJ9 (symlink), RJ13/RJ13b (case) and RJ14 (foreign repo)
# exercise it through the whole fence, and the RRP section exercises this file directly — the
# first direct tests this logic has ever had.
# ------------------------------------------------------------------------------------------------
#
# USAGE
#   repo-rel-path.sh <toplevel> <path>
#
#   <toplevel> is the checkout the answer should be relative to — the value the caller already
#   holds from `git rev-parse --show-toplevel`. <path> may be empty, which is not an error: the
#   caller passes `ADR`/`PLAN` unconditionally and those are legitimately empty on Express.
#
#   stdout, with NO trailing newline: the repo-relative path (`docs/manifests/x.yml`), or <path>
#   byte-for-byte when it is not inside <toplevel>, or nothing at all for an empty <path>.
#
# EXIT CONTRACT (ADR-0132 §D4, shared by the four scripts that issue adds)
#   0  RAN. Includes every fall-back case above — "this path is not in your checkout" is an
#      answer, not a failure.
#   2  bad invocation: wrong argument count, or an empty <toplevel>.
#   3  COULD NOT RUN: <toplevel> does not resolve to a git repository.
#
#      EXIT 3 IS AN ADDITION, NOT PART OF THE VERBATIM REPRODUCTION. The original `rel()` had no
#      such path — it fell through to a per-path exit 0 for every guard, because the fence had
#      already established the repository above it and there was no way to call the function
#      without one. Wrapped as a standalone script that anyone can invoke, "the caller handed me a
#      <toplevel> that is not a repository at all" stops being unreachable and becomes the
#      environment failure the uniform 0/2/3 contract exists to name. Do NOT "restore" it to match
#      the old `rel()` by deleting this branch: a fourth silent fall-back would report a
#      never-consulted repository as a clean answer, which is the confusion ADR-0076 §THE RULE
#      forbids. The chain's own call site cannot reach it — the fence exits 3 with
#      `PREFLIGHT_NOREPO` before it ever gets here.
#
# The git call that decides exit 3 is also what <toplevel> is normalised through, so a caller that
# passes a subdirectory of a checkout is answered relative to the checkout's real top. The one
# in-chain caller always passes a real toplevel, so this is robustness, not behaviour anyone relies
# on.
#
# IT NEVER WRITES. No temp file, no transition, nothing in the project tree.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no here-strings.
set -u

SELF="repo-rel-path"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: repo-rel-path.sh <toplevel> <path>

Prints <path> relative to <toplevel>, or <path> unchanged if it is not inside that checkout.
Exit: 0 answered | 2 bad invocation | 3 could not run (<toplevel> is not a git repository)
EOF
  exit 2
}

[ $# -eq 2 ] || usage "expected exactly 2 arguments, got $#"
TOP="$1"
TARGET="$2"
[ -n "$TOP" ] || usage "the toplevel argument is empty"

_top=$(git -C "$TOP" rev-parse --show-toplevel 2>/dev/null) || {
  printf '%s: could not run — not a git repository: %s\n' "$SELF" "$TOP" >&2
  exit 3
}
[ -n "$_top" ] || {
  printf '%s: could not run — git reported no toplevel for: %s\n' "$SELF" "$TOP" >&2
  exit 3
}

# --- verbatim from the fence's rel(), with the positional parameters made real -------------------
[ -n "$TARGET" ] || exit 0
_d=$(dirname "$TARGET")
[ -d "$_d" ] || { printf '%s' "$TARGET"; exit 0; }
_t2=$(git -C "$_d" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$TARGET"; exit 0; }
{ [ -n "$_t2" ] && [ "$_t2" -ef "$_top" ]; } || { printf '%s' "$TARGET"; exit 0; }
printf '%s%s' "$(git -C "$_d" rev-parse --show-prefix 2>/dev/null)" "$(basename "$TARGET")"
exit 0
