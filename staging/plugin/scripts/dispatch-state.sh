#!/bin/bash
# dispatch-state.sh v1.0 — THE one place that answers "did the subagent I dispatched under this id
# actually finish?" (issue #435, ADR-0139).
#
# WHY THIS EXISTS. CC 2.1.232 made non-teammate agent spawns run in the background by default in
# interactive sessions. Measured 2026-08-14: an `Agent()` call returns immediately carrying dispatch
# metadata and nothing else; the agent's report arrives later, as a notification. Every Agent-tool
# dispatch site in this system signalled completion through the transcript, so every one of them now
# reads a channel that no longer carries the answer:
#
#   A6, Step 5 batch coder   the coder ends its report with `PATTERN: DONE tasks=<N> files=<M>` and
#                            the controller greps "the agent report text" for it. The tool result
#                            never contains that line, so a healthy dispatch reads as truncated.
#   A1, Step 4.5 tracer      the verdict is computed from `git diff --stat=999` run straight after
#                            dispatch. Measured early the diff is smaller than the truth and the
#                            budget check returns CLEAN — a false green no assertion can see,
#                            because the assertion measures the right thing at the wrong moment.
#
# The Workflow dispatch path never had this defect: its final subagent writes
# `.claude/step5-report.json` and the controller reads the FILE, with a declared branch for absent
# (concept-to-code's step5-report.json read contract). That path is also immune to the 2.1.232
# change — measured, `agent()` in a workflow script resolves to the agent's real value. This carries
# the Workflow path's own answer across to the Agent-tool path rather than inventing a second one.
#
# AND THE AGENT-TOOL PATH IS THE ONE THAT RUNS. Of 59 manifests, 52 carry `hook_verified: false`;
# of the modes actually recorded, 32 are `agent_batch` against 2 `workflow`. An unattended run can
# never reach the immune path: the Step 5 autopilot default records `hook_verified = false` and
# takes this fallback, "never takes the Workflow path unless hooks were already verified true".
#
# THE AGENT ALWAYS WRITES THE FACT. WHAT CHANGES BY CLASS IS WHICH ROOT HOLDS IT.
#
#   class=inline    no worktree. The agent writes `<project_root>/.claude/dispatch/<id>.done` as
#                   its last action, and the caller passes <project_root>.
#   class=isolated  `isolation: worktree`. The agent's writes land inside its own worktree, so it
#                   writes `<worktree>/.claude/dispatch/<id>.done`, and the caller passes
#                   <worktree> — which is `<project_root>/.claude/worktrees/agent-<id>/`, a path
#                   the orchestrator can read directly. No merge is involved.
#
# WHY NOT THE MERGE-BACK. The first draft made the ORCHESTRATOR write the fact once the merge-back
# and base-fork audit block succeeded, on the reasoning that the merge-back is what makes an
# isolated agent's work visible. It does not prove completion: the merge-back runs
# `git -C "$WT" status --porcelain` and `git merge`, and a worktree caught mid-write merges cleanly
# and succeeds. It would have certified a half-finished batch as DONE, which is the same false green
# in a new place. Reading the agent's own marker at its own path proves what the merge-back cannot.
#
# Either way this script reads exactly one thing, so the class never leaks into it — the caller
# already knows which root it dispatched against, and passing the wrong one yields NONE, not a
# wrong DONE.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE, then on the token. `weakening-scan.sh` and
# `diff-budget-check.sh`, invoked a few lines away in the same Step 5 checkpoint, are REPORTERS:
# they always exit 0 and signal on stdout with a `CLEAN` sentinel. Do not copy one block's branching
# into the other — ADR-0048 §D5 had to write that out at its own call site once already.
#
# IT REPORTS A FACT. IT DOES NOT DECIDE. Two call sites apply OPPOSITE policies to the same
# `PENDING`: the Step 5 checkpoint must not advance to the next batch, and the Step 4.5 tracer
# bullet must not emit any verdict at all — not even a failing one, because "the coder has not
# finished" is not evidence about the slice. `manifest-field-state.sh`'s "IT REPORTS. IT DOES NOT
# DECIDE." makes the same argument for the same reason, and this script refuses a verdict for it.
#
# IT NEVER WRITES. Not the state dir, not the markers, not a temp file. A checker that creates the
# thing it checks would answer its own question.
#
# CONTRACT
#   stdout, exactly one line, <TOKEN>|<detail>. Split on the FIRST separator:
#   `${out%%|*}` is the token, `${out#*|}` the detail.
#
#     NONE|                       nothing declared under that id. The ordinary pre-dispatch case.
#     PENDING|                    dispatch declared (`<id>.started` present), no completion fact.
#     DONE|tasks=<N> files=<M>    completion fact present and well formed.
#     PARTIAL|<raw>               completion fact present, payload does not parse. NOT done: a
#                                 half-written marker is the shape a killed agent leaves behind.
#     UNREADABLE|                 a marker exists and cannot be read.
#
#   exit 0  a token was determined and printed. PENDING, PARTIAL and UNREADABLE ARE determinations.
#   exit 2  bad invocation: wrong arity, empty argument, root is not a directory, or an id that
#           would escape the state directory.
#   exit 3  the check DID NOT RUN: the state directory exists and cannot be listed.
#
# WHY "nothing declared" IS A TOKEN AND NOT EXIT 3, and why it is resolved FIRST. Absence is a fact
# about the INPUT; exit 3 is a fact about the ENVIRONMENT. ADR-0076 §CONTRACT draws that line for
# `manifest-field-state.sh`, `manifest-entry-state.sh`'s NONE-before-exit-3 ordering draws it
# again, and it is drawn a third time here: a caller asking about an id that was never dispatched
# must get NONE on any machine, including one with no other state to read.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="dispatch-state"
STATE_SUBDIR=".claude/dispatch"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: dispatch-state.sh <project-root> <dispatch-id>

Reports whether a dispatched subagent's completion fact is present. Reports; never decides,
never writes.

stdout: NONE| | PENDING| | DONE|tasks=<N> files=<M> | PARTIAL|<raw> | UNREADABLE|
Exit:   0 determined | 2 bad invocation | 3 could not run (state dir unlistable)
EOF
  exit 2
}

[ $# -eq 2 ] || usage "expected exactly 2 arguments, got $#"
ROOT="$1"
ID="$2"
[ -n "$ROOT" ] || usage "project root is empty"
[ -n "$ID" ] || usage "dispatch id is empty"
[ -d "$ROOT" ] || usage "project root is not a directory: $ROOT"

# An id is a filename component, never a path. A caller that builds one from a batch label cannot be
# allowed to reach outside the state directory, and the refusal is bad invocation rather than a
# token: there is no fact to report about an id that cannot exist.
case "$ID" in
  */*|*'\'*|.|..|*..*) usage "dispatch id must be a single path component with no '..': $ID" ;;
esac

DIR="$ROOT/$STATE_SUBDIR"
STARTED="$DIR/$ID.started"
DONE="$DIR/$ID.done"

# ORDERING, AND IT IS NOT THE OBVIOUS ONE. `manifest-entry-state.sh`'s NONE-before-exit-3 ordering
# resolves its absence token first, and the first draft of this script copied that ordering
# verbatim. It produced a false `NONE` — measured: with the state directory at `chmod 000`, `[ -e
# "$STARTED" ]` is FALSE because the test cannot stat through an unsearchable directory, so a batch
# that HAD been dispatched reported "nothing was ever dispatched under this id". A check that could
# not run reported a clean result, which is the defect this script's own exit 3 exists to prevent.
#
# The difference from the manifest helper is that its absence test is a stat on a path the caller
# named, while this one stats INSIDE a directory that may itself be unreadable. So the split is by
# the directory, not by the marker:
#
#   directory absent       -> NONE. Nothing was ever dispatched here, answerable on any machine,
#                             and no permission on a non-existent path can make that wrong.
#   directory unsearchable -> exit 3. Every answer about its contents would be a guess.
#
# ADR-0076's line still holds — absence is a fact about the INPUT, exit 3 about the ENVIRONMENT.
# What changed is which absence can be established without reading the environment.
if [ ! -d "$DIR" ]; then
  printf 'NONE|\n'
  exit 0
fi

if [ ! -x "$DIR" ] || [ ! -r "$DIR" ]; then
  printf '%s: %s exists and cannot be searched — the check DID NOT RUN\n' "$SELF" "$DIR" >&2
  exit 3
fi

if [ ! -e "$STARTED" ] && [ ! -e "$DONE" ]; then
  printf 'NONE|\n'
  exit 0
fi

if [ -e "$DONE" ]; then
  if [ ! -f "$DONE" ] || [ ! -r "$DONE" ]; then
    printf 'UNREADABLE|\n'
    exit 0
  fi
  PAYLOAD=$(head -1 "$DONE" 2>/dev/null) || PAYLOAD=""
  # Collapse newlines defensively so the one-line contract holds even on a malformed marker.
  PAYLOAD=$(printf '%s' "$PAYLOAD" | tr '\n\r' '  ')
  case "$PAYLOAD" in
    tasks=[0-9]*\ files=[0-9]*)
      # Guard the shape rather than trusting the glob: `tasks=1x files=2` matches the pattern above.
      _t=${PAYLOAD#tasks=}; _t=${_t%% *}
      _f=${PAYLOAD##*files=}; _f=${_f%% *}
      case "$_t$_f" in
        *[!0-9]*) printf 'PARTIAL|%s\n' "$PAYLOAD" ;;
        *)        printf 'DONE|tasks=%s files=%s\n' "$_t" "$_f" ;;
      esac
      ;;
    *)
      printf 'PARTIAL|%s\n' "$PAYLOAD"
      ;;
  esac
  exit 0
fi

if [ -e "$STARTED" ] && [ ! -r "$STARTED" ]; then
  printf 'UNREADABLE|\n'
  exit 0
fi

printf 'PENDING|\n'
exit 0
