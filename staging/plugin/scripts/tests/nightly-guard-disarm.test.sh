#!/bin/bash
# nightly-guard-disarm.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash nightly-guard-disarm.test.sh
#
# TWO ISSUES, ONE FILE, because measuring showed neither explains the 2026-07-31 incident alone.
#
#   #321 — `.claude/nightly-state/active` is created in Phase 1 and removed ONLY in Phase 2, so a
#          session that dies leaves the guard armed in the human's own later sessions, with nothing
#          documenting the way out.
#   #323 — `is_forbidden_publish`'s destination rule ran over the WHOLE command while the two rules
#          above it are scoped to the push segment, so `git push -u origin feat/x && gh pr create
#          --base main` read the PR's `--base` as the push's destination.
#
# A stale marker on its own blocks only FORBIDDEN publishes; an ordinary `git push` still passes the
# halt checks. What turned an ordinary publish into a forbidden one is #323. Section F pins that.
#
# WHAT A PID WOULD HAVE COST, recorded because the issue proposed one. The marker is written from a
# Bash tool call whose subprocess exits within milliseconds, so `$$` records a pid that is always
# dead — a liveness check on it would report every live run as stale. Session id and timestamp are
# the two real signals; section O uses only those.
#
# DERIVED-GUARD PATTERN — not an instance. Nothing here derives a population at run time, so the
# count-guard idiom is deliberately absent (ADR-0086 §D1). `Z1` is an assertion floor, which is a
# different thing: it catches an assertion that VANISHES, not a derivation that stops resolving.
#
# A PLANT FOR A NEGATIVE ASSERTION MUST MAKE THE THING HAPPEN, NOT DELETE THE GUARD. Five of the
# first draft's plants did not fire, and all five were the same mistake: `F6`, `O5`, `G2`, `G3` and
# `S2` assert that something must NOT occur — a command must not be refused, a live run must not be
# told to disarm, a bare `touch` must be gone — and removing the mechanism leaves every one of them
# trivially satisfied. The mutation has to INVERT the condition (`!=` → `=`), or REINTRODUCE the
# thing being banned. Deleting code only tests positive assertions.
#
# `F3` and `F6` are pinned by the same mutation, and that is recorded rather than papered over:
# both are cases of one property (the destination rule is scoped to the push segment), and the only
# mutation that breaks F6 is the whole-command revert that also breaks F3. F6 earns its place as a
# CASE, not as independent evidence.
#
# plant: F3 | plugin/scripts/nightly-guard.sh | grep -Eq 'git push[^|;&]*[ :/+](main|master)([ ]|$)' | grep -Eq '(^|[ :/+])(main|master)([ ]|$)'
# plant: F6 | plugin/scripts/nightly-guard.sh | grep -Eq 'git push[^|;&]*[ :/+](main|master)([ ]|$)' | grep -Eq '(^|[ :/+])(main|master)([ ]|$)'
# plant: O2 | plugin/scripts/nightly-disarm.sh | if [ -n "$OWNER" ] && [ -n "$CUR" ] && [ "$OWNER" = "$CUR" ]; then | if false; then
# plant: O3 | plugin/scripts/nightly-disarm.sh | NOTE="note: the marker records no session_id | NOTE=""; _skip="note: the marker records no session_id
# A REPLACEMENT CANNOT CONTAIN A NEWLINE, so a multi-statement mutation must carry its own `;`.
# O5's first draft was `echo "..." >&2 exit 0`, which matched exactly one site, passed PC2, and did
# something else entirely: collapsed onto one line, `exit 0` becomes two ARGUMENTS to `echo`, no
# exit happens, control falls through to the next branch — which still exits 2, so the assertion
# went on passing. It read as "O5 pins nothing". Reproduced by hand with a real newline, the
# assertion failed correctly. **Inspect what a plant produced before believing what it reports**
# (ADR-0090), and note that PC2's exactly-one-match check cannot see this class at all.
# plant: O5 | plugin/scripts/nightly-disarm.sh | echo "nightly-disarm: usage: nightly-disarm.sh <project-root>" >&2 exit 2 | echo "usage" >&2; exit 0
# plant: O6 | plugin/scripts/nightly-disarm.sh | echo "nightly-disarm: not a directory: $ROOT" >&2 exit 2 | echo "not a directory" >&2; exit 0
# plant: D1 | plugin/scripts/nightly-disarm.sh | "$SDIR/started-at" "$ROOT/.claude/needs-human"; do | ; do
# plant: D4 | plugin/scripts/nightly-disarm.sh | echo "DISARM: NOTHING-ARMED — no $STATE_SUBDIR and no needs-human under $ROOT" | echo "DISARM: CLEARED"
# plant: G2 | plugin/scripts/nightly-guard.sh | [ -n "$OWNER" ] && [ -n "$SID" ] && [ "$OWNER" != "$SID" ] | [ -n "$OWNER" ] && [ -n "$SID" ] && [ "$OWNER" = "$SID" ]
# plant: G3 | plugin/scripts/nightly-guard.sh | if [ -n "$OWNER" ] && [ -n "$SID" ] && [ "$OWNER" != "$SID" ]; then | if [ -n "$SID" ] && [ "$OWNER" != "$SID" ]; then
# plant: G5 | plugin/scripts/nightly-guard.sh | [ -f "$CWD/$STATE_SUBDIR/active" ] || exit 0 | true
# plant: S1 | plugin/skills/nightly-autopilot/SKILL.md | printf 'session_id=%s\nstarted_at=%s\n' | printf 'nothing=%s\n'
# plant: S2 | plugin/skills/nightly-autopilot/SKILL.md | "${CLAUDE_CODE_SESSION_ID:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \ > "$PWD/.claude/nightly-state/active" | touch "$PWD/.claude/nightly-state/active"
# plant: S4 | plugin/skills/nightly-autopilot/SKILL.md | bash ~/.claude/hooks/nightly-disarm.sh "$PWD" | rm -f "$PWD/.claude/nightly-state/active"
# plant: P1 | sync-to-claude.sh | plugin/scripts/nightly-disarm.sh|hooks/nightly-disarm.sh | plugin/scripts/nightly-guard.sh|hooks/nightly-guard.sh

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
REPO=$(cd "$STAGING/.." && pwd)

GUARD="$SCRIPTS/nightly-guard.sh"
DISARM="$SCRIPTS/nightly-disarm.sh"
NA="$SKILLS/nightly-autopilot/SKILL.md"
RUNBOOK="$REPO/docs/RUNBOOK-nightly-autopilot.md"
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# mk_root <name> — a scratch project root. NOT a counter incremented inside $(...): that runs in a
# SUBSHELL, so every call returns the same directory and the fixtures accumulate into each other
# (the bug ADR-0096 and ADR-0110 each hit in turn).
mk_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude/nightly-state"
  printf '%s' "$_r"
}

# arm <root> <session-id> — write a marker in the current format.
arm() {
  printf 'session_id=%s\nstarted_at=%s\n' "$2" "2026-07-31T21:03:40Z" > "$1/.claude/nightly-state/active"
}

# =====================================================================================
# F. #323 — the destination rule. `is_forbidden_publish` is EXTRACTED AND RUN, never
# re-implemented: a second copy of the regex in the test would pass whatever it was written against
# (the whole point of ADR-0086's criterion, applied to an assertion instead of a helper).

FN="$TMPROOT/fn.sh"
awk '/^is_forbidden_publish\(\)/,/^}/' "$GUARD" > "$FN"
if [ "$(grep -c . "$FN")" -ge 10 ]; then
  ok "F0: is_forbidden_publish extracted ($(grep -c . "$FN") lines)"
else
  bad "F0: extraction returned $(grep -c . "$FN") lines — the function moved or was renamed"
fi

verdict() {
  { cat "$FN"; printf 'if is_forbidden_publish "$1"; then echo HALT; else echo ALLOW; fi\n'; } > "$TMPROOT/v.sh"
  bash "$TMPROOT/v.sh" "$1"
}

# F1-F3: the issue's own three probe cases, measured live against the deployed shape. Each half is
# allowed; before the fix the two joined by `&&` were refused as a push to main.
[ "$(verdict 'git push -u origin feat/x')" = "ALLOW" ] \
  && ok "F1: a plain feature-branch push is allowed" \
  || bad "F1: a plain feature-branch push is refused"
[ "$(verdict 'gh pr create --base main --fill')" = "ALLOW" ] \
  && ok "F2: opening a PR against main is allowed" \
  || bad "F2: opening a PR against main is refused"
[ "$(verdict 'git push -u origin feat/x && gh pr create --base main --fill')" = "ALLOW" ] \
  && ok "F3: push + PR-to-main joined by && is allowed (the #323 case)" \
  || bad "F3: the ordinary publish shape is still refused as a push to main"

# F4-F8: every genuine push-to-main form still halts. R-03, and these are what a naive fix breaks.
for c in 'git push origin main' \
         'git push origin master' \
         'git push origin HEAD:refs/heads/main' \
         'git push origin +main' \
         'rm -rf build && git push origin main'; do
  [ "$(verdict "$c")" = "HALT" ] \
    && ok "F4: still forbidden — $c" \
    || bad "F4: NO LONGER FORBIDDEN — $c"
done

# F5: force and merge rules are untouched by the scoping change (regression guard on the siblings).
[ "$(verdict 'git push -f origin feat/x')" = "HALT" ] \
  && ok "F5: a force push is still forbidden" || bad "F5: force push no longer forbidden"
[ "$(verdict 'git commit --no-verify -m x && git push origin feat/x')" = "HALT" ] \
  && ok "F5b: --no-verify is still forbidden" || bad "F5b: --no-verify no longer forbidden"

# F6/F7: two cases the issue does NOT name, and they are the ones a whole-command rule gets wrong in
# the opposite direction. A PR *to* main is allowed; only *pushing to* main is forbidden.
[ "$(verdict 'gh pr create --base main && git push origin feat/x')" = "ALLOW" ] \
  && ok "F6: PR-to-main followed by a feature-branch push is allowed" \
  || bad "F6: refused — the destination rule is reading the PR's base again"
[ "$(verdict 'git push origin feat/main-thing')" = "ALLOW" ] \
  && ok "F7: a branch whose name merely contains 'main' is allowed" \
  || bad "F7: refused a branch named feat/main-thing"

# F8: and the dangerous inverse of F6 — pushing to main first, PR second — must still halt.
[ "$(verdict 'git push origin main && gh pr create --base feat/x')" = "HALT" ] \
  && ok "F8: push-to-main followed by anything still halts" \
  || bad "F8: push-to-main escaped because a later segment was benign"

# =====================================================================================
# O. #321 — ownership. R-04 is the one that must hold by construction.

# O1: a foreign session disarms.
R=$(mk_root o1); arm "$R" "session-AAA"
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] && [ ! -f "$R/.claude/nightly-state/active" ] \
   && printf '%s' "$OUT" | grep -q 'DISARM: CLEARED'; then
  ok "O1: a marker armed by another session is cleared"
else
  bad "O1: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# O2: the OWNING session is refused, and the marker survives. R-04, and it is a property of the
# mechanism rather than a sentence in a SKILL.md.
R=$(mk_root o2); arm "$R" "session-AAA"
OUT=$(CLAUDE_CODE_SESSION_ID=session-AAA bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "1" ] && [ -f "$R/.claude/nightly-state/active" ] \
   && printf '%s' "$OUT" | grep -q 'REFUSED'; then
  ok "O2: the session that armed the marker cannot disarm it, and the marker survives"
else
  bad "O2: rc=$RC marker=$( [ -f "$R/.claude/nightly-state/active" ] && echo kept || echo REMOVED )"
fi

# O3: a legacy bare-touch marker carries no session_id. ABSENT is not FOREIGN and not CORRUPT
# (ADR-0076): it disarms, with a note. Refusing here would strand exactly the people this exists
# for — the ones whose marker predates the fix.
R=$(mk_root o3); : > "$R/.claude/nightly-state/active"
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] && [ ! -f "$R/.claude/nightly-state/active" ] \
   && printf '%s' "$OUT" | grep -q 'no session_id'; then
  ok "O3: a legacy empty marker disarms and says why it could not name an owner"
else
  bad "O3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# O4: no session id in the environment at all — the disarm must not refuse on an unknown current
# session. Failing closed here would be failing closed on the recovery path, which is backwards.
R=$(mk_root o4); arm "$R" "session-AAA"
OUT=$(env -u CLAUDE_CODE_SESSION_ID bash "$DISARM" "$R" 2>&1); RC=$?
[ "$RC" = "0" ] && [ ! -f "$R/.claude/nightly-state/active" ] \
  && ok "O4: an unknown current session still disarms (the recovery path never fails closed)" \
  || bad "O4: rc=$RC — recovery refused because the current session id was unset"

# O5/O6: invocation errors are exit 2, distinct from both 0 and 3.
OUT=$(bash "$DISARM" 2>&1); [ $? = "2" ] \
  && ok "O5: no argument is exit 2" || bad "O5: no argument did not exit 2"
OUT=$(bash "$DISARM" "$TMPROOT/does-not-exist" 2>&1); [ $? = "2" ] \
  && ok "O6: a non-directory root is exit 2" || bad "O6: a non-directory root did not exit 2"

# O7: DID-NOT-RUN is exit 3 and is NOT reported as success. "Nothing was armed" and "I could not
# look" must not be the same answer — a blocked human reads 0 as "you are free now".
R="$TMPROOT/o7"; mkdir -p "$R/.claude"; : > "$R/.claude/nightly-state"
OUT=$(bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'DID-NOT-RUN'; then
  ok "O7: an unreadable state path is exit 3, never a clean 0"
else
  bad "O7: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# =====================================================================================
# D. The debris. Clearing only `active` leaves four other ways to stay blocked.

R=$(mk_root d1); arm "$R" "session-AAA"
printf 'RED'          > "$R/.claude/nightly-state/build-status"
printf 'blocker\n'    > "$R/.claude/nightly-state/rtf-blocker"
printf 'limit=1\nspent=9\n' > "$R/.claude/nightly-state/token-budget"
printf '2026-07-31T21:03:40Z' > "$R/.claude/nightly-state/started-at"
printf 'a reason\n'   > "$R/.claude/needs-human"
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?
LEFT=""
for f in active build-status rtf-blocker token-budget started-at; do
  [ -e "$R/.claude/nightly-state/$f" ] && LEFT="$LEFT $f"
done
[ -e "$R/.claude/needs-human" ] && LEFT="$LEFT needs-human"
if [ "$RC" = "0" ] && [ -z "$LEFT" ]; then
  ok "D1: the whole transient set is cleared, not just the marker"
else
  bad "D1: rc=$RC still present:$LEFT"
fi

# D2: and each removal is NAMED. A disarm that silently removes six files is one nobody can audit.
if [ "$(printf '%s\n' "$OUT" | grep -c 'removed:')" -ge 6 ]; then
  ok "D2: every removed file is reported by name"
else
  bad "D2: only $(printf '%s\n' "$OUT" | grep -c 'removed:') removals reported"
fi

# D3: the point of D1 — after the disarm, the guard's own --check gate passes. Before ADR-0112 a
# stale RED build-status halted --check REGARDLESS of the marker, so a marker-only disarm looked
# like it worked while the human stayed blocked.
bash "$GUARD" --check "$R" >/dev/null 2>&1
[ $? = "0" ] && ok "D3: --check passes after the disarm (the stale RED no longer halts)" \
             || bad "D3: --check still halts after a successful disarm"

# D4: nothing armed is a distinct, honest answer — not a fabricated CLEARED.
R=$(mk_root d4); rmdir "$R/.claude/nightly-state"
OUT=$(bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'NOTHING-ARMED'; then
  ok "D4: a repo that never ran nightly reports NOTHING-ARMED, not CLEARED"
else
  bad "D4: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# =====================================================================================
# G. The guard's halt message. R-03, and the direction that matters is when it stays SILENT.

hook_event() { printf '{"session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "$3"; }

# G1: a foreign marker + a forbidden publish -> the halt names the owner and the disarm command.
R=$(mk_root g1); arm "$R" "session-AAA"
OUT=$(hook_event "session-BBB" "$R" "git push origin main" | bash "$GUARD" 2>&1); RC=$?
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'nightly-disarm.sh' \
   && printf '%s' "$OUT" | grep -q 'session-AAA'; then
  ok "G1: a foreign marker's halt names the owner and the disarm command"
else
  bad "G1: rc=$RC — $(printf '%s' "$OUT" | tail -2 | head -1)"
fi

# G2: the SAME session gets no hint. A live roadmap must never be invited to disarm itself — that
# is the one thing R-04 forbids, and the halt text here must be what it always was.
R=$(mk_root g2); arm "$R" "session-AAA"
OUT=$(hook_event "session-AAA" "$R" "git push origin main" | bash "$GUARD" 2>&1); RC=$?
if [ "$RC" = "2" ] && ! printf '%s' "$OUT" | grep -q 'nightly-disarm.sh'; then
  ok "G2: the owning session's halt message carries no disarm invitation"
else
  bad "G2: a live run was told how to disarm itself"
fi

# G3: a legacy marker with no owner also gets no hint — the guard cannot tell whose it is, and
# guessing is worse than staying quiet.
R=$(mk_root g3); : > "$R/.claude/nightly-state/active"
OUT=$(hook_event "session-BBB" "$R" "git push origin main" | bash "$GUARD" 2>&1); RC=$?
if [ "$RC" = "2" ] && ! printf '%s' "$OUT" | grep -q 'nightly-disarm.sh'; then
  ok "G3: an ownerless marker produces no hint rather than a guess"
else
  bad "G3: the guard guessed an owner it does not have"
fi

# G4: the #323 fix reaches the real hook path, not just the extracted function.
R=$(mk_root g4); arm "$R" "session-AAA"
hook_event "session-BBB" "$R" "git push -u origin feat/x && gh pr create --base main" \
  | bash "$GUARD" >/dev/null 2>&1
[ $? = "0" ] && ok "G4: the ordinary publish shape passes the live hook with the guard armed" \
             || bad "G4: still halted through the hook path"

# G5: no marker at all -> inert. The one line that keeps this guard out of manual work.
R=$(mk_root g5)
hook_event "session-BBB" "$R" "git push origin main" | bash "$GUARD" >/dev/null 2>&1
[ $? = "0" ] && ok "G5: with no marker the guard is inert even on a push to main" \
             || bad "G5: the guard blocked manual work with no nightly run armed"

# =====================================================================================
# S / R / P. The prose and the wiring. Needles target MECHANISMS, never the name of the thing being
# asserted about (rule 12), and prose clauses match a flattened, undecorated copy — a clause is the
# same clause whether it wraps, is bolded, or has a word in backticks (ADR-0073/0076/0080/0098).
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr -d '`*'; }
flat "$NA" > "$TMPROOT/na.flat"
flat "$RUNBOOK" > "$TMPROOT/rb.flat"

# S1/S2: §3.1 writes the owner into the marker instead of touching it.
grep -q 'session_id=%s' "$NA" && ok "S1: §3.1 records session_id in the marker" \
                              || bad "S1: §3.1 still writes a contentless marker"
if grep -q "touch \"\$PWD/.claude/nightly-state/active\"" "$NA"; then
  bad "S2: §3.1 still uses a bare touch"
else
  ok "S2: the bare touch is gone from §3.1"
fi

# S3: and it forbids inventing a separate started-at file — the defect that produced a real,
# unwritten-by-anything file in this repository.
grep -q 'Do not invent a separate file' "$TMPROOT/na.flat" \
  && ok "S3: §3.1 forbids a separate started_at file and says why" \
  || bad "S3: §3.1 leaves started_at without a specified home"

# S4: §4 disarms via the script, not rm -f. The plain remove is how a RED build-status survives.
if grep -q 'nightly-disarm.sh' "$NA" && ! grep -q 'rm -f "\$PWD/.claude/nightly-state/active"' "$NA"; then
  ok "S4: §4 disarms through the script, and the bare rm -f is gone"
else
  bad "S4: §4 still removes only the marker"
fi

# R1: the RUNBOOK section is titled with words a blocked human actually types. R-02.
grep -q 'The guard is still armed and I cannot push' "$RUNBOOK" \
  && ok "R1: the RUNBOOK carries a section titled as a blocked human would search" \
  || bad "R1: no discoverable disarm section"

# R2: 'Aborting a run' no longer reads as nothing-left-to-do. It is the section a human lands on
# after stopping a run, and its reassurance was the defect — not merely a missing section.
grep -q 'There is one thing left to do: disarm the guard' "$TMPROOT/rb.flat" \
  && ok "R2: 'Aborting a run' now names the leftover state" \
  || bad "R2: 'Aborting a run' still reads as complete"

# R3: the exit codes are documented where the human reads them, including that 3 is not success.
grep -q 'not the same as "nothing was armed"' "$TMPROOT/rb.flat" \
  && ok "R3: the RUNBOOK distinguishes exit 3 from a clean result" \
  || bad "R3: exit 3 is undocumented or reads as success"

# P1: the new script is wired for deployment. Without this it is inert on every machine.
# `pairs-completeness.test.sh` covers the direction "every PAIRS src exists"; this covers the one
# that matters here — that the entry exists at all.
grep -q 'plugin/scripts/nightly-disarm.sh|hooks/nightly-disarm.sh' "$SYNC" \
  && ok "P1: nightly-disarm.sh has a PAIRS entry" \
  || bad "P1: nightly-disarm.sh would never reach ~/.claude"

# P2: and it is made executable on deploy, like its siblings. A non-executable hook fails at the
# moment someone is already blocked, which is the worst possible time to find out.
grep -q 'hooks/nightly-disarm.sh" 2>/dev/null' "$SYNC" \
  && ok "P2: the deploy preserves the executable bit on nightly-disarm.sh" \
  || bad "P2: nightly-disarm.sh is deployed without +x"

# P3: both scripts parse.
bash -n "$GUARD" 2>/dev/null && ok "P3: nightly-guard.sh parses" || bad "P3: nightly-guard.sh does not parse"
bash -n "$DISARM" 2>/dev/null && ok "P3b: nightly-disarm.sh parses" || bad "P3b: nightly-disarm.sh does not parse"

# =====================================================================================
# Z1: assertion floor. A floor, not an exact count: it catches an assertion that VANISHES without
# needing a bump on every addition (ADR-0083 §D3 — a suite reporting fewer assertions does not read
# as broken, and nobody watches the number).
TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -ge 33 ]; then
  ok "Z1: assertion floor met ($TOTAL)"
else
  bad "Z1: only $TOTAL assertions executed, expected >= 33 — did an extraction return empty?"
fi

echo "----"
echo "nightly-guard-disarm.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
