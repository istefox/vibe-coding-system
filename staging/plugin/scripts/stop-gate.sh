#!/bin/bash
# Stop gate v3.1: v3 + additionalContext (CC 2.1.163) for test-fail feedback to Claude.
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block","reason":..} = block.
# Never exit non-zero / never block on internal error (fail-open, spec §7).
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
TRUST="${STOP_GATE_TRUST_FILE:-$DIR/trust}"
N="${STOP_GATE_MAX_REENTRY:-3}"; case "$N" in ''|*[!0-9]*) N=3;; esac
# ADR-0137 D4 — the ceiling, environment half. This validation is byte-identical to the single
# line it replaces (unset, empty or non-digit => 120), on purpose: STOP_GATE_TEST_TIMEOUT is the
# caller's own lever and stays UNBOUNDED — TMO_MAX bounds the FILE only, and bounding the
# variable too would change existing behaviour for every caller already setting it. TMO_ENV
# records that the environment supplied the value, which is what gives it precedence over
# .claude/test-timeout further down; the file cannot be read here because $ROOT is not known yet.
TMO_MAX=900
TMO=120; TMO_ENV=0
case "${STOP_GATE_TEST_TIMEOUT:-}" in
  ''|*[!0-9]*) ;;
  *) TMO="$STOP_GATE_TEST_TIMEOUT"; TMO_ENV=1;;
esac

# norm_path: canonical trust path for $1 (a dir that exists).
# pwd -P resolves symlinks (/var → /private/var on macOS).
# On Darwin, lowercase to match case-insensitive FS semantics.
# Fail-open: if cd fails, echo $1 unchanged.
norm_path() {
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

DIRTY="$DIR/$SID.dirty"
CF="$DIR/$SID.count"
# ADR-0156 D1 — the signature of the LAST failure this session blocked on. The budget is spent by
# DISTINCT failures, not by repeats: three blocks on one failing assertion are one piece of
# information, not three (issue #477). Measured before this existed: 5 of 16 sessions that ever
# blocked reached the cap and stood down for the rest of the session, every one of them on repeats
# of a failure the operator had already read.
SF="$DIR/$SID.sig"
[ ! -f "$DIRTY" ] && exit 0

emit_block() {  # $1 = reason text; $2 = test output to append to reason (optional)
  local count=0
  [ -f "$CF" ] && count=$(cat "$CF" 2>/dev/null || echo 0)
  case "$count" in ''|*[!0-9]*) count=0;; esac

  # ADR-0156 D1/D2 — a repeat of the failure already reported spends nothing AND says nothing.
  # The pairing is what keeps D1 from being a bypass: a DIFFERENT failure — which is what a real
  # regression is, by definition — hashes differently, so it still blocks and still spends. The
  # gate becomes louder about new information and silent about old, the opposite of today.
  #
  # Hashed from the OUTPUT, never the exit code (ADR-0156 A4): a suite failing two different
  # assertions exits 1 both times, so keying on the code would dedupe two findings into one and
  # silently drop the second — a false negative in the direction this gate exists to prevent.
  #
  # A failure whose output varies run to run (a timestamp, a temp path, a seed) reads as new every
  # time and spends the budget exactly as it does today. That is the SAFE degradation direction —
  # never quieter than the old behaviour — and it is a stated limit, not a defect to rediscover.
  local sig="" prev=""
  if [ -n "${2:-}" ]; then
    printf '%s' "$2" > "$DIR/.$SID.sigin" 2>/dev/null \
      && sig=$(sha256_of "$DIR/.$SID.sigin") || sig=""
    rm -f "$DIR/.$SID.sigin" 2>/dev/null
  fi
  [ -f "$SF" ] && prev=$(cat "$SF" 2>/dev/null || true)
  if [ -n "$sig" ] && [ "$sig" = "$prev" ]; then
    echo "stop-gate: identical failure to the last block this session — already reported, budget not spent (ADR-0156 D1/D2). A different failure still blocks." >&2
    exit 0
  fi

  if [ "$count" -ge "$N" ]; then
    echo "stop-gate: anti-loop guardrail active — unblocked after $N entries. Verify manually." >&2
    exit 0
  fi
  count=$((count + 1))
  echo "$count" > "$CF" 2>/dev/null || true
  [ -n "$sig" ] && { printf '%s' "$sig" > "$SF" 2>/dev/null || true; }

  # ADR-0156 D5 — at the cap the stand-down is announced in the REASON, the channel an operator
  # actually reads, not on stderr alone. This file's own timeout-path comment already says why:
  # a guard that stops guarding silently is this repository's signature failure. The block path
  # stood down just as quietly until #477.
  if [ "$count" -ge "$N" ]; then
    set -- "$1
stop-gate: this is the FINAL block of this session. The anti-loop guardrail is now disarmed — further turns will not be checked (cap STOP_GATE_MAX_REENTRY=$N, ADR-0156 D5). Verify manually from here." "${2:-}"
  fi

  if [ -n "${2:-}" ]; then
    # Deliver test output inside reason (root-level field only — hookSpecificOutput is not
    # valid for Stop events and causes JSON validation errors in Claude Code).
    jq -nc --arg r "$1" --arg c "$2" \
      '{decision:"block",reason:($r + "\n\n" + $c)}' \
      2>/dev/null \
      || printf '{"decision":"block","reason":"verify tests before closing"}\n'
  else
    jq -nc --arg r "$1" '{decision:"block",reason:$r}' 2>/dev/null \
      || printf '{"decision":"block","reason":"verify tests before closing"}\n'
  fi
  exit 0
}

ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done

if [ -z "$ROOT" ]; then
  emit_block "Code modified without verification. Run the project tests, or declare the command in .claude/test-cmd (or 'NONE' to opt-out)."
fi
# v4: read/hash test-cmd on the pre-normalization (case-preserving) path — same fix as
# approve-test-cmd.sh (issue #38). ROOT is normalized afterward, into a SEPARATE
# variable, for the case-invariant trust LOOKUP only: run_with_timeout below still
# needs to cd into the real path, so ROOT itself is never overwritten in this script.
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)

[ "$CMD" = "NONE" ] && exit 0
[ -z "$CMD" ] && exit 0          # empty/unreadable test-cmd → fail-open (spec §7)
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else return 1; fi
}
H=$(sha256_of "$TCF") || { echo "stop-gate: no sha256 tool — fail-open" >&2; exit 0; }
[ -z "$H" ] && exit 0
ROOT_NORM=$(norm_path "$ROOT")
LINE=$(printf '%s\t%s' "$H" "$ROOT_NORM")
TRUSTED=0
[ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null && TRUSTED=1

if [ "$TRUSTED" -ne 1 ]; then
  emit_block "Project test command not approved (TOFU). Review $TCF and run: bash ~/.claude/hooks/approve-test-cmd.sh \"$ROOT\" — tests will then run automatically at end of task."
fi
# ---------------------------------------------------------------------------------------------
# ADR-0137 D2/D3 — the path predicate. Optional, project-owned, and read at the SAME $ROOT the
# walk above already found for .claude/test-cmd: one walk finds both, so in a monorepo they
# cannot diverge (R-04). Placed AFTER the TOFU check on purpose — the two blocking paths (no
# test-cmd found; test-cmd present but untrusted) are untouched, and the list is deliberately not
# a way to silence them.
#
# The list EXCLUDES, never includes: the suite is skipped only when EVERY recorded path is
# excluded, so one unknown path still arms (R-03). Every unknown here resolves to ARMING — no
# list, an unreadable list, an unreadable or path-less marker, a path with no relative form, any
# internal error. This change removes firings, so its inert and unknown states are the strict one
# (ADR-0055 §D2), and with no list at this root the whole block is a no-op (R-02).
IGN="$ROOT/.claude/test-ignore"
if [ -f "$IGN" ] && [ -r "$IGN" ] && [ -s "$DIRTY" ] && [ -r "$DIRTY" ]; then
  case "$ROOT" in */) RPFX="$ROOT";; *) RPFX="$ROOT/";; esac
  EXCLUDED=0; UNEXCLUDED=0; WHY=""
  while IFS= read -r p || [ -n "$p" ]; do
    [ -z "$p" ] && continue
    # Not an absolute path: unmatchable by construction (mark-dirty.sh records a newline-bearing
    # path in exactly this shape). Arm and stop looking — no pattern can exclude it.
    case "$p" in /*) ;; *) UNEXCLUDED=1; break;; esac
    # Root-relative form via the QUOTED strip, so a glob metacharacter in $ROOT stays literal
    # (verified on bash 3.2.57). A path outside $ROOT is left unchanged by the strip and has no
    # relative form at all: rel stays empty and only an absolute pattern can exclude it (R-08).
    rel=""; s=${p#"$RPFX"}; [ "$s" != "$p" ] && rel="$s"
    hit=""
    while IFS= read -r pat || [ -n "$pat" ]; do
      # Blank lines, and lines whose first NON-BLANK character is '#', are skipped. The same
      # trim feeds the pattern: the skip rule already declares a leading run of blanks to be no
      # part of the pattern, so keeping it would make an indented pattern silently unmatchable.
      lead=${pat%%[! 	]*}; pat=${pat#"$lead"}
      case "$pat" in ''|'#'*) continue;; esac
      case "$pat" in '~'*) pat="$HOME${pat#\~}";; esac   # ~ expands, landing in the next case
      case "$pat" in */) pat="$pat*";; esac              # trailing / = directory prefix
      # $pat is UNQUOTED here so it is a glob, and that is safe: bash does not re-expand the
      # result of an expansion, so a pattern whose text is a command substitution is matched as
      # literal text and never executed (pinned by SGP18).
      case "$pat" in
        /*) case "$p" in $pat) hit="$pat"; break;; esac;;
        *)  if [ -n "$rel" ]; then case "$rel" in $pat) hit="$pat"; break;; esac; fi;;
      esac
    done < "$IGN"
    if [ -n "$hit" ]; then
      EXCLUDED=$((EXCLUDED + 1))
      case "$WHY" in *" $hit"*) ;; *) WHY="$WHY $hit";; esac
    else
      UNEXCLUDED=1; break
    fi
  done < "$DIRTY"
  # EXCLUDED > 0 guards the denominator: a marker of nothing but blank lines excludes nothing,
  # and "no candidates" must not read as "all excluded" (CLAUDE.md rule 7).
  if [ "$UNEXCLUDED" -eq 0 ] && [ "$EXCLUDED" -gt 0 ]; then
    # One line, on the arming side only: a guard that stops guarding must say so. The marker is
    # deliberately LEFT IN PLACE — a skipped turn must not clear the session's record, which is
    # cleared on a green run and only there (R-05).
    echo "stop-gate: suite skipped — all $EXCLUDED recorded path(s) excluded by $IGN (matched:$WHY)" >&2
    exit 0
  fi
fi
# ---------------------------------------------------------------------------------------------
# ADR-0137 D4 — the ceiling, file half. Read at the SAME $ROOT the walk above found, so the
# ceiling and the test command it bounds can never come from different projects in a monorepo.
# Absent means 120 EXACTLY, so every other project on the machine is unaffected (R-09).
#
# It is deliberately NOT part of the TOFU hash: a ceiling is a bound, not a command, and it can
# only ever extend how long an ALREADY-APPROVED command runs — which is precisely what TMO_MAX
# exists to bound. sha256_of, $TCF and the trust line above are untouched.
#
# Read AFTER the path predicate, so a turn the predicate declined never emits a ceiling
# complaint about a suite it was never going to run (SPEC control flow, steps 5 then 6).
if [ "$TMO_ENV" -eq 0 ] && [ -f "$ROOT/.claude/test-timeout" ] && [ -r "$ROOT/.claude/test-timeout" ]; then
  TMOV=$(head -n 1 "$ROOT/.claude/test-timeout" 2>/dev/null | tr -d '[:space:]')
  TMO_BAD=0
  # Not a positive integer at most TMO_MAX => fall back to the DEFAULT, never to whatever `case`
  # happens to accept. Three rejections, in an order that keeps each test safe: the digit test
  # first, then a LENGTH test (a digit run long enough to overflow bash's 64-bit arithmetic must
  # not be able to buy itself a pass at `-gt`), and only then the arithmetic comparisons.
  case "$TMOV" in ''|*[!0-9]*) TMO_BAD=1;; esac
  [ "$TMO_BAD" -eq 0 ] && [ "${#TMOV}" -gt 9 ] && TMO_BAD=1
  [ "$TMO_BAD" -eq 0 ] && { [ "$TMOV" -eq 0 ] || [ "$TMOV" -gt "$TMO_MAX" ]; } && TMO_BAD=1
  if [ "$TMO_BAD" -eq 1 ]; then
    # One line, naming BOTH the value rejected and the value used: a project that asked for 1800
    # and got 120 must be able to find out why, rather than discovering it by stopwatch.
    echo "stop-gate: ignoring $ROOT/.claude/test-timeout value '$TMOV' — not a positive integer of at most ${TMO_MAX}s; using ${TMO}s" >&2
  else
    TMO="$TMOV"
  fi
fi
run_with_timeout() {  # $1=secs $2=cmdstring → returns rc; 124=timeout 125=cannot-run
  if command -v timeout >/dev/null 2>&1; then timeout "$1" bash -c "$2"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$1" bash -c "$2"; return $?
  else
    bash -c "$2" & local p=$!
    ( sleep "$1"; kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null ) & local w=$!
    wait "$p" 2>/dev/null; local rc=$?
    kill -9 "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [ "$rc" -eq 137 ] && return 124
    return "$rc"
  fi
}
OUT="$DIR/.$SID.testout"
run_with_timeout "$TMO" "cd $(printf %q "$ROOT") && ( $CMD )" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 124 ]; then
  # ADR-0137 D5 — a timeout spends from the SAME per-session budget a block spends from, read
  # with emit_block's own idiom (missing or non-numeric counter reads as 0). Before this, the
  # counter was incremented only inside emit_block, which a timeout never reaches: a timing-out
  # suite re-charged its full ceiling on every remaining Stop of the session, forever and
  # uncounted. One counter, one budget, spent by either failure mode.
  tcount=0
  [ -f "$CF" ] && tcount=$(cat "$CF" 2>/dev/null || echo 0)
  case "$tcount" in ''|*[!0-9]*) tcount=0;; esac
  tcount=$((tcount + 1))
  echo "$tcount" > "$CF" 2>/dev/null || true
  rm -f "$OUT" 2>/dev/null
  if [ "$tcount" -ge "$N" ]; then
    # At the cap the marker is REMOVED, which is the timeout analogue of emit_block's anti-loop
    # unblock: the session stops paying the ceiling on every further Stop. Said on stderr,
    # because a guard that stops guarding silently is this repository's signature failure.
    rm -f "$DIRTY" 2>/dev/null
    echo "stop-gate: test timed out after ${TMO}s — disarmed for this session, $tcount timeout(s) reached the STOP_GATE_MAX_REENTRY cap of $N. Marker removed; verify manually." >&2
  else
    echo "stop-gate: test timed out after ${TMO}s (attempt $tcount of $N) — fail-open" >&2
  fi
  exit 0
fi
# 125, 126 and 127 keep today's message and do NOT increment. The counter bounds COST, and a
# command that cannot be found or cannot be executed exits INSTANTLY and costs nothing — folding
# these in with 124 would spend a session's whole budget on a free failure. That leaves a
# permanently non-executable test-cmd arming forever at zero cost: pre-existing, unchanged, and
# recorded here so its absence is not later read as coverage (ADR-0137 D5). The negative
# direction — 127 must not increment — is asserted by SGP13.
if [ "$RC" -eq 125 ] || [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
  echo "stop-gate: test timeout/not executable — fail-open" >&2
  rm -f "$OUT" 2>/dev/null; exit 0
fi
if [ "$RC" -eq 0 ]; then
  # ADR-0156 D3 — a verified tree refreshes the budget. Before this, $CF was written in two places
  # (here-adjacent emit_block, and the timeout branch) and removed in NONE, so a session that
  # reached the cap stayed disarmed permanently, even after the condition that disarmed it was
  # gone. The signature goes with it: after a green run the next failure is new information again.
  rm -f "$DIRTY" "$OUT" "$CF" "$SF" 2>/dev/null || true
  exit 0
fi
TAIL=$(tail -c 600 "$OUT" 2>/dev/null); rm -f "$OUT" 2>/dev/null
emit_block "Tests failed (exit $RC). Failing test output provided in context below." "$TAIL"
exit 0
