#!/bin/bash
# permission-mode-state.sh v1.0 — THE one place that answers "what permission mode is this session
# ACTUALLY in?" (issue #320, ADR-0110).
#
# WHY THIS EXISTS. `autopilot` states its first launch precondition three times in prose —
# set a non-blocking permission mode — and Phase 0's eight checks verified it NOWHERE. Every other
# precondition it checks (opt-in marker, TOFU trust, gh auth, CI) fails loudly and early. This one
# failed silently and late: on 2026-07-31 pre-flight printed PASSED, the guard armed, the roadmap
# started, and the chain died at its first Gate 0 write with nobody present to answer the prompt.
# It is also the only precondition whose failure is GUARANTEED fatal rather than conditional.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE, then on the token.
# `weakening-scan.sh` is a REPORTER — always exits 0, signals `CLEAN` on stdout. Do not copy one
# block's branching into the other.
#
# IT READS ONLY. No writes anywhere, no temp file in the project tree.
#
# WHERE THE ANSWER COMES FROM, and why not the obvious place:
#
#   NOT `~/.claude/settings.json`. That holds `permissions.defaultMode` — the STORED DEFAULT. A
#   session started with `--permission-mode`, or switched at runtime with Shift+Tab, never writes
#   there. So a stored `acceptEdits` would PASS while the session actually runs `auto` and dies:
#   that is the very failure this check exists to prevent, so reading it would be wrong in exactly
#   the direction that matters. Measured 2026-08-01: settings.json said `auto` while the live
#   session was in `plan`.
#
#   NOT the environment. The nine CLAUDE* variables a skill's Bash can see carry no permission
#   field. Checked before designing anything.
#
#   THE SESSION TRANSCRIPT. `permissionMode` is recorded as a TOP-LEVEL key on `user` entries and
#   on a dedicated `type: "permission-mode"` entry emitted when the mode changes. The LAST such
#   value is the effective mode. The transcript is located from `CLAUDE_CODE_SESSION_ID` — the
#   correct variable name, established with a citation in ADR-0029 after the issue that introduced
#   it guessed a name that does not exist.
#
# BUILD-STAMPED, AND THAT MATTERS. Measured on CC 2.1.220: 39 of 42 local transcripts carry the
# field, and the two real exceptions are both CC 2.1.219. The field is new. ADR-0016's v2.1.154
# experience is the precedent — the substrate moves — so `UNOBSERVABLE` is a first-class answer
# rather than an error, and this header should be re-measured after a major CC bump.
#
# WHY A JSON PARSER AND NOT grep. The value is read as a TOP-LEVEL key, so a `permissionMode` that
# appears inside some nested string — a tool result quoting this very script's output, say — can
# never be mistaken for the session's own state. Measured on a transcript containing exactly that
# case: grep 114, parser 114, no divergence. The naive grep survives ONLY because JSON escapes the
# quotes of nested strings, which is an accidental property of the format rather than a designed
# guarantee. Relying on it would be rule 12 at run time.
#
# `import json` is STDLIB, so unlike its siblings in this directory this script needs no PyYAML —
# and a test fixture that redirects HOME (which hides per-user site-packages, ADR-0090's trap) does
# not break it.
#
# CONTRACT
#   stdout, exactly one line, <TOKEN>|<detail>. Split on the FIRST separator.
#
#     NONBLOCKING|<mode>    `acceptEdits` or `bypassPermissions` — the two `autopilot`
#                           declares as non-blocking. An unattended run may proceed.
#
#                           THE TWO ARE NOT EQUIVALENT, AND A CALLER MUST NOT SAY THEY ARE
#                           (issue #339). `acceptEdits` auto-accepts EDITS; a Bash command outside
#                           `permissions.allow` still prompts. Measured on this machine: the
#                           allowlist holds 16 Bash entries (git status/diff/log/add/commit,
#                           pytest, ruff, black, mypy, npm run/test, rg, fd, gh issue, pip
#                           install) and the chain's own surface — `bash ~/.claude/skills/*/
#                           scripts/manifest-*.sh`, sed, awk, mkdir, `git push`, `gh pr create`,
#                           the project's test-cmd — is not among them. Only `bypassPermissions`
#                           delivers "no prompt can fire". Both tokens stay NONBLOCKING because a
#                           repo whose allowlist DOES cover its Bash surface makes `acceptEdits`
#                           sufficient, and deciding that is the caller's job, not this reporter's
#                           (ADR-0076 §D2). What the caller owes the operator is a message that
#                           distinguishes them.
#     BLOCKING|<mode>       `auto`, `plan`, `default`, `manual` — a prompt or a classifier denial
#                           can fire, and there is nobody to answer it.
#     UNCLASSIFIED|<mode>   a mode this enumeration does not know. `dontAsk` is the one that exists
#                           today. NOT known-bad: see below.
#     UNOBSERVABLE|<why>    no session id, no transcript found, or a transcript with no
#                           `permissionMode` in it (a pre-2.1.220 build).
#
#   exit 0  a token was determined and printed. UNOBSERVABLE IS a determination.
#   exit 2  bad invocation (this script takes no arguments).
#   exit 3  the check DID NOT RUN: no python3, or no readable projects directory at all.
#
# UNOBSERVABLE IS A TOKEN, NOT EXIT 3, and the distinction is the same one ADR-0076 draws and #319
# had to relearn a week ago: "this build does not record the mode" is a fact about the INPUT, and
# exit 3 is a fact about the ENVIRONMENT. A caller that cannot tell them apart reports a missing
# interpreter and an old Claude Code with one sentence, and that sentence is wrong for one of them.
#
# `dontAsk` IS REJECTED AS UNCLASSIFIED, DELIBERATELY. Its semantics could not be established from
# the CC binary, and for a pre-flight the safe direction is to refuse the unknown: aborting a run
# that would have worked costs a night, while passing one that stalls costs a night AND leaves
# half-written state behind. Callers must say "unclassified, not known-bad" in their message, so an
# operator is not told their mode is unsafe when nobody has measured it.
#
# transcript-scan-exempt: reads the LAST permissionMode, not the first user entry, because the
# whole point is the mode in force NOW; and the #127 self-arming hazard cannot apply here, since
# the value is taken as a TOP-LEVEL JSON key rather than matched as text, so a tool result quoting
# `permissionMode` cannot be mistaken for the session's own state. Pinned by PM8 in
# permission-mode-state.test.sh, with a nested-decoy fixture built for exactly that case.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="permission-mode-state"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: permission-mode-state.sh

Reports the EFFECTIVE permission mode of the current session, read from its transcript.
Reports; never decides, never writes. Takes no arguments.

stdout: NONBLOCKING|<mode> | BLOCKING|<mode> | UNCLASSIFIED|<mode> | UNOBSERVABLE|<why>
Exit:   0 determined | 2 bad invocation | 3 could not run (no python3, no projects directory)
EOF
  exit 2
}

[ $# -eq 0 ] || usage "expected no arguments, got $#"

PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SID" ]; then
  printf 'UNOBSERVABLE|no CLAUDE_CODE_SESSION_ID in the environment\n'
  exit 0
fi

# Locating the projects directory is an ENVIRONMENT question; not finding this session's file
# inside it is an INPUT question. Hence one exit 3 and one token.
[ -d "$PROJECTS" ] || { printf '%s: %s is not a directory — the check DID NOT RUN\n' "$SELF" "$PROJECTS" >&2; exit 3; }

# Glob rather than re-deriving the directory-name slug from $PWD: the slug rule is Claude Code's,
# it is undocumented, and a second implementation of it here would be a copy that can disagree
# (ADR-0086's criterion). A session id is unique, so the glob is exact.
TRANSCRIPT=""
for _c in "$PROJECTS"/*/"$SID".jsonl; do
  [ -f "$_c" ] && { TRANSCRIPT="$_c"; break; }
done
if [ -z "$TRANSCRIPT" ]; then
  printf 'UNOBSERVABLE|no transcript for session %s under %s\n' "$SID" "$PROJECTS"
  exit 0
fi

command -v python3 >/dev/null 2>&1 \
  || { printf '%s: python3 not available — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }

# json is stdlib: no third-party import, so a HOME-redirected fixture cannot break this.
MODE=$(python3 -c '
import sys, json
last = ""
try:
    fh = open(sys.argv[1], errors="replace")
except Exception:
    print("__READ_FAILED__"); raise SystemExit(0)
with fh:
    for line in fh:
        try:
            d = json.loads(line)
        except Exception:
            # Deliberate swallow, and the only one here: a transcript is APPEND-ONLY and is being
            # written while this runs, so its last line can legitimately be half-flushed. Skipping
            # an unparseable line is correct; a failure of the interpreter itself is not swallowed
            # at all — see the PYRC guard below.
            continue
        if not isinstance(d, dict):
            continue
        v = d.get("permissionMode")
        if isinstance(v, str) and v:
            last = v
print(last)
' "$TRANSCRIPT" 2>/dev/null); PYRC=$?

# The embedded program catches its own file errors and always exits 0, so a non-zero status here
# means the INTERPRETER failed — an environment fact, exit 3. Without this guard an interpreter
# crash produces an empty $MODE and falls into the branch below, which would tell the operator
# "a pre-2.1.220 build does not write it" — a cause that is not the cause. Reporting the wrong
# reason for a state is the defect class this whole file exists to close; it is not allowed to
# reappear inside it. Found by `weakening-scan.sh`'s advisory `swallowed-error` heuristic.
if [ "$PYRC" -ne 0 ]; then
  printf '%s: python3 exited %s reading %s — the check DID NOT RUN\n' "$SELF" "$PYRC" "$TRANSCRIPT" >&2
  exit 3
fi

if [ "$MODE" = "__READ_FAILED__" ]; then
  printf 'UNOBSERVABLE|transcript %s could not be read\n' "$TRANSCRIPT"
  exit 0
fi
if [ -z "$MODE" ]; then
  printf 'UNOBSERVABLE|no permissionMode recorded in %s (a pre-2.1.220 build does not write it)\n' "$TRANSCRIPT"
  exit 0
fi

case "$MODE" in
  acceptEdits|bypassPermissions) printf 'NONBLOCKING|%s\n'  "$MODE" ;;
  auto|plan|default|manual)      printf 'BLOCKING|%s\n'     "$MODE" ;;
  *)                             printf 'UNCLASSIFIED|%s\n' "$MODE" ;;
esac
exit 0
