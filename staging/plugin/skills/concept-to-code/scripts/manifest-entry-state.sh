#!/bin/bash
# manifest-entry-state.sh v1.0 — THE one place that answers "there is already a manifest at this
# path; which entry point can reach it?" (issue #319, ADR-0109).
#
# WHY THIS EXISTS. The chain had two entry points and they refused each other in a loop:
#
#   Form A  `manifest-init.sh`'s `Refuse double-init for same slug same day` guard is
#           `[ -f "$manifest" ]` -> exit 2, "use resume". The guard is on
#           FILE EXISTENCE, never on state, so no transition can unblock it and Form C (abort)
#           preserves the file, so it does not either.
#   Form B  the branch table routed "any step before step_4_session_boundary" to "resume not
#           necessary, continue in current session" — naming a command that DOES NOT EXIST. The
#           in-session entry point is Form A, which is what just refused.
#
# Measured 2026-08-01 on the deployed copy, before any of this was written: Form B resolved 2 of
# the 13 standard states, and THREE matched no branch at all — `step_4_session_boundary`,
# `step_6_review`, `step_7_commit`. ADR-0095 had disclosed only the second. The first is the one
# that mattered: `SKILL.md` Gate 4 "Abort chain" tells the operator to resume from it, and
# `project-conductor` Step 3 and Step 5 branch B both act on it by invoking Form B.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE, then on the token.
# `weakening-scan.sh`, invoked a few lines away in the same Step 5 checkpoint, is a REPORTER: it
# always exits 0 and signals on stdout with a `CLEAN` sentinel. Do not copy one block's branching
# into the other — that confusion is what ADR-0048 §D5 had to write out at its own call site.
#
# IT REPORTS A FACT. IT DOES NOT DECIDE. The token says which entry point CAN reach the manifest;
# what an unattended run then does with a non-`ADOPTABLE` answer — per-feature skip versus
# run-level halt — was decided by ADR-0111 (issue #324) and is applied by `project-conductor`, not
# here: `TERMINAL` marks that one feature `[~]` and the roadmap continues, every other token writes
# the run-level `needs-human` marker and halts. That policy stays at the caller because only the
# conductor owns PROJECT.md and the roadmap; this script still decides nothing.
#
# IT NEVER WRITES. No transition, no overwrite, no deletion, no temp file in the project tree.
# R-02 of the issue is held by construction rather than by care.
#
# CONTRACT
#   stdout, exactly one line, <TOKEN>|<detail>. Split on the FIRST separator:
#   `${out%%|*}` is the token, `${out#*|}` the detail. <detail> is the manifest's `current_step`
#   wherever one could be read, and empty otherwise.
#
#     NONE|            no file at that path. The ordinary Form A case: create a new manifest.
#     ADOPTABLE|<s>    standard/legacy chain, in flight, in a state BEFORE the session boundary.
#                      The current session continues it in place. This is the state #319 wedged.
#     BOUNDARY|<s>     `step_4_session_boundary` — Gate 4 was presented and never answered. The
#                      current session re-presents Gate 4.
#     RESUMABLE|<s>    `ready_for_implementation` or `step_5_implementation`. Form B, and only
#                      Form B: these are the two states its table already resolves.
#     LATE|<s>         `step_6_review` or `step_7_commit`. Named rather than left to fall through
#                      the table, which is what they did before this existed.
#     UNRESUMABLE|<s>  express or hybrid, non-terminal. `SKILL.md` "Resume semantics" forbids Form
#                      B for these paths outright, so the current session is the only option.
#     TERMINAL|<s>     `completed`, `failed` or `aborted`, by `current_step` OR by `status` — Form
#                      C sets `status` alone and leaves `current_step` untouched, so reading only
#                      one of the two misses every aborted chain.
#     UNKNOWN|<s>      a `current_step` the validator does not recognise. Corruption or a hand
#                      edit; never silently routed as adoptable.
#     UNREADABLE|      the file exists and does not parse as a YAML mapping.
#
#   exit 0  a token was determined and printed. UNREADABLE and UNKNOWN ARE determinations.
#   exit 2  bad invocation.
#   exit 3  the check DID NOT RUN: no python3, no PyYAML, the sibling helpers are missing, or the
#           state enum could not be derived.
#
# WHY "no file" AND "unparseable" ARE TOKENS AND NOT EXIT 3. The first draft of this script folded
# both into exit 3 as "could not run". That is #319 reproduced one level down: the caller could no
# longer tell "nothing is there, go ahead and create one" — the common, legitimate, overwhelmingly
# most frequent case — from "this machine has no PyYAML". Absence and corruption are facts about
# the INPUT; exit 3 is a fact about the ENVIRONMENT. ADR-0076 §CONTRACT draws that line for
# `manifest-field-state.sh` and it is drawn again here for the same reason.
#
# THE STATE ENUM IS DERIVED, NOT COPIED. `manifest-validate.sh` owns the list of valid states and
# is the authority. A second copy here would answer differently the day either file gains a state,
# and the answer it would give is `UNKNOWN` on a perfectly valid manifest — so by ADR-0086's
# criterion (extract only when two copies giving different answers would be a DEFECT) this one
# derives. The derivation is count-guarded: a validator refactor that stops matching yields exit 3,
# never a silently empty set that reads as "every state is unknown".
#
# Validity is judged on `current_step` ALONE, not by running `manifest-validate.sh` — that script
# carries 28 invariants and a manifest can fail one for a reason entirely unrelated to routing
# (ADR-0078's dead `project_root` is the live example, on five of this repository's own manifests).
# Refusing to route an adoptable chain because of an unrelated invariant would be a stricter defect
# than the one being fixed.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="manifest-entry-state"
HERE=$(cd "$(dirname "$0")" && pwd)
FIELD_STATE="$HERE/manifest-field-state.sh"
VALIDATE="$HERE/manifest-validate.sh"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: manifest-entry-state.sh <manifest.yml>

Reports which entry point can reach an existing manifest. Reports; never decides, never writes.

stdout: NONE| | ADOPTABLE|<s> | BOUNDARY|<s> | RESUMABLE|<s> | LATE|<s> | UNRESUMABLE|<s>
        | TERMINAL|<s> | UNKNOWN|<s> | UNREADABLE|
Exit:   0 determined | 2 bad invocation | 3 could not run (env, helpers, or enum derivation)
EOF
  exit 2
}

[ $# -eq 1 ] || usage "expected exactly 1 argument, got $#"
MANIFEST="$1"
[ -n "$MANIFEST" ] || usage "manifest path is empty"

# No file is a legitimate answer, and it is checked before anything that could exit 3: a caller
# asking about a path that holds nothing must get NONE even on a machine with no PyYAML.
if [ ! -e "$MANIFEST" ]; then
  printf 'NONE|\n'
  exit 0
fi
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] \
  || { printf '%s: path exists but is not a readable file: %s\n' "$SELF" "$MANIFEST" >&2; exit 2; }

[ -f "$FIELD_STATE" ] || { printf '%s: %s not found — the check DID NOT RUN. Run: bash <repo>/staging/sync-to-claude.sh --apply\n' "$SELF" "$FIELD_STATE" >&2; exit 3; }
[ -f "$VALIDATE" ]    || { printf '%s: %s not found — the check DID NOT RUN. Run: bash <repo>/staging/sync-to-claude.sh --apply\n' "$SELF" "$VALIDATE" >&2; exit 3; }

# read_field <name> -> echoes the value, or the literal UNREADABLE, or returns 3.
read_field() {
  _st=$(bash "$FIELD_STATE" "$MANIFEST" "$1" 2>/dev/null)
  _rc=$?
  [ "$_rc" -eq 0 ] || return 3
  case "$_st" in
    UNREADABLE)  printf 'UNREADABLE\n' ;;
    PRESENT\|*)  printf '%s\n' "${_st#PRESENT|}" ;;
    ABSENT\|*)   printf '\n' ;;
    *)           return 3 ;;
  esac
  return 0
}

STEP=$(read_field current_step)   || { printf '%s: could not read current_step — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }
[ "$STEP" = "UNREADABLE" ] && { printf 'UNREADABLE|\n'; exit 0; }

STATUS=$(read_field status)       || { printf '%s: could not read status — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }
CHAIN=$(read_field chain_path)    || { printf '%s: could not read chain_path — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }

# A manifest that parses but carries no current_step is not routable, and is not the same as one
# that does not parse. Invariant 4 of the validator calls this corruption in every state.
[ -n "$STEP" ] || { printf 'UNKNOWN|\n'; exit 0; }

# --- state enum, derived from the authority ------------------------------------------------
# Matches the validator's own `echo "<state>" >> "$VALID_STEPS"` construction. If that
# construction changes shape the count guard below fires and this script reports exit 3, which is
# the whole point of guarding a denominator rather than a match count (ADR-0085 §T0b).
KNOWN=$(grep -oE '^echo "[a-z0-9_]+" >>? "\$VALID_STEPS"' "$VALIDATE" 2>/dev/null \
        | sed -E 's/^echo "//; s/" >>? "\$VALID_STEPS"$//')
KNOWN_N=$(printf '%s\n' "$KNOWN" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "${KNOWN_N:-0}" -lt 25 ]; then
  printf '%s: derived only %s states from %s (expected >= 25) — the check DID NOT RUN.\n' \
    "$SELF" "${KNOWN_N:-0}" "$VALIDATE" >&2
  printf '%s: the enum construction in manifest-validate.sh changed shape; fix this derivation.\n' "$SELF" >&2
  exit 3
fi
printf '%s\n' "$KNOWN" | sed '/^$/d' | grep -Fxq "$STEP" || { printf 'UNKNOWN|%s\n' "$STEP"; exit 0; }

# --- classification ------------------------------------------------------------------------
# Order is load-bearing. TERMINAL first: Form C sets `status: aborted` and leaves `current_step`
# wherever it was, so an aborted step_0_init chain must not read as ADOPTABLE.
case "$STEP" in
  completed|failed|aborted) printf 'TERMINAL|%s\n' "$STEP"; exit 0 ;;
esac
case "$STATUS" in
  completed|failed|aborted) printf 'TERMINAL|%s\n' "$STEP"; exit 0 ;;
esac

# Express and Hybrid next: their states are disjoint from the standard ones, and `SKILL.md`
# "Resume semantics" forbids Form B for both paths regardless of how far along they are.
case "$CHAIN" in
  express|hybrid) printf 'UNRESUMABLE|%s\n' "$STEP"; exit 0 ;;
esac
case "$STEP" in
  step_e*|gate_e*|step_h*|gate_h*) printf 'UNRESUMABLE|%s\n' "$STEP"; exit 0 ;;
esac

case "$STEP" in
  step_4_session_boundary)                        printf 'BOUNDARY|%s\n'  "$STEP" ;;
  ready_for_implementation|step_5_implementation) printf 'RESUMABLE|%s\n' "$STEP" ;;
  step_6_review|step_7_commit)                    printf 'LATE|%s\n'      "$STEP" ;;
  *)                                              printf 'ADOPTABLE|%s\n' "$STEP" ;;
esac
exit 0
