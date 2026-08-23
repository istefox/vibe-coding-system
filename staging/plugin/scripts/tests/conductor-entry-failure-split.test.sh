#!/bin/bash
# conductor-entry-failure-split.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash conductor-entry-failure-split.test.sh
#
# THE RULE — `project-conductor` must not answer "this feature did not complete" with "the run
# cannot be trusted". A KNOWN, CONTAINED, per-feature entry failure appends to
# `.claude/autopilot-state/skipped-features`, marks the feature `[~]`, and the roadmap continues; a
# genuinely unknown state writes the run-level `.claude/needs-human` marker and halts. Issue #324,
# ADR-0111. ADR-0060 §D3 drew this exact line for `spec-from-issue`'s two skips and Gate 2c's;
# Step 5 branch C never got it, so the blast radius survived through a second door.
#
# WHAT MOVED THE DESIGN, recorded because the assertions below only make sense against it:
#
#   The issue's cause 1 is stale in its stated form. `manifest-init.sh` exit 2 is no longer how a
#   same-day collision reaches branch C from inside `concept-to-code` — step 4b (ADR-0109)
#   intercepts before manifest-init runs, and the collision surfaces as `ENTRY-ROUTE: TERMINAL`.
#   The cause is real; the door changed, and the new door carries a token.
#
#   The conductor calls `manifest-init.sh` ITSELF, outside that guard — cause 1's remaining door,
#   which is why `conductor-step4-init-guard` exists (section G).
#
#   Cause 2's evidence is NOT at branch C and cannot be classified there. With no SPEC the chain
#   routes greenfield and Step 1 dispatches `interview-driver`, which is interactive; the manifest
#   is left at `step_0_init`/`in_progress`, which the classifier reads as ADOPTABLE —
#   indistinguishable from any other mid-flight state. So it is settled at Step 4, where the
#   conductor already knows (section S). That is the issue's own instruction applied: move the
#   classification to where the evidence is.
#
# THE TOKEN ALONE DECIDES, and section B pins both directions of that. `TERMINAL` is a decided end
# with its reason in the manifest. A crash leaves a NON-terminal state, so ADR-0047 §D5's
# anti-test-weakening halt — which never transitions — stays run-level with no special case. B6 is
# what would fail if someone "simplified" the fallthrough into a skip.
#
# DERIVED-GUARD PATTERN — instance 10 (ADR-0086). Derives: nothing at run time; this file asserts
# three named fences and one writer list. The count-guard idiom is deliberately NOT copied here,
# because there is no derivation to guard. Before adding one, read ADR-0086 §D1.
#
# plant: S1 | plugin/skills/project-conductor/SKILL.md | cp "$_spec" "$_root/SPEC.md" || { echo "SPEC-COPY: DID-NOT-RUN | true || { echo "SPEC-COPY: DID-NOT-RUN
# plant: S2 | plugin/skills/project-conductor/SKILL.md | "$_issue" "$_feature" "$_issue" >> "$_root/.claude/autopilot-state/skipped-features" | "$_issue" "$_feature" "$_issue" > "$_root/.claude/needs-human"
# S3 retargeted (issue #385 dispatch, Batch 3): the awk match program moved out of the two
# SKILL.md fences and into mark-roadmap-skipped.sh (ADR-0132 §D2), so the old needle — spanning the
# comment immediately above the fence's inline awk call and the call itself — matched zero sites in
# SKILL.md; the file's own explanatory comment and the invocation are now ~65 lines apart. Retargeted
# at the invocation itself: forcing the compared value to a literal "NOMATCH" breaks the whole-line
# match for any real feature title, which is exactly what marks S3's row [~].
# plant: S3 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | -v f="$FEATURE" | -v f="NOMATCH"
# plant: G2 | plugin/skills/project-conductor/SKILL.md | ENTRY-INIT: TERMINAL (${_out#*|}) | ENTRY-INIT: ADOPT (${_out#*|})
# plant: G5 | plugin/skills/project-conductor/SKILL.md | echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply" exit 3 fi # Constructed here | exit 3 fi # Constructed here
# plant: B1 | plugin/skills/project-conductor/SKILL.md | "$_feature" "${_out#*|}" >> "$_root/.claude/autopilot-state/skipped-features" | "$_feature" "${_out#*|}" > "$_root/.claude/needs-human"
# plant: B4 | plugin/skills/project-conductor/SKILL.md | "$_feature" "$_out" > "$_root/.claude/needs-human" | "$_feature" "$_out" >> "$_root/.claude/autopilot-state/skipped-features"
# plant: B6 | plugin/skills/project-conductor/SKILL.md | case "${_out%%|*}" in TERMINAL) | case "${_out%%|*}" in TERMINAL|RESUMABLE|ADOPTABLE)
# plant: B9 | plugin/skills/project-conductor/SKILL.md | echo "BRANCH-C: DID-NOT-RUN — classifier missing: $_mes" | printf 'x' > "$_root/.claude/needs-human"; echo "BRANCH-C: DID-NOT-RUN — classifier missing: $_mes"
# plant: B9b | plugin/skills/project-conductor/SKILL.md | [ "$_rc" -eq 0 ] || { echo "BRANCH-C: DID-NOT-RUN — $_out"; exit 3; } | [ "$_rc" -eq 0 ] || { _out="TERMINAL|guessed"; }
#
# MR1-MR9 (issue #385 dispatch, Batch 3): the first direct plants for mark-roadmap-skipped.sh's own
# assertions, now that they are green. MR5 needed a `;` inserted before `exit N` in the replacement,
# not just a space: the source has `>&2` and `exit N` on TWO lines, and collapsing them onto one line
# without a `;` makes `exit N` two more ARGUMENTS to printf (which cycles its format string over
# them) rather than a second statement — verified live (ADR-0112's `echo "..." >&2 exit 0` lesson,
# met again with printf; recovery-preflight.test.sh's RRP6 hit the identical shape the same hour).
# plant: MR1 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | print "- [~] " f "  (skipped)" | print "- [ ] " f "  (skipped)"
# plant: MR2 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | else print } | else print "MUTATED-" $0 }
# plant: MR3 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | $0 == "- [ ] " f | $0 ~ "- [ ] " f
# plant: MR4 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | exit 2 | exit 0
# plant: MR5 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | readable roadmap file at %s\n' "$SELF" "$MD" >&2 exit 3 | readable roadmap file at %s\n' "$SELF" "$MD" >&2; exit 0
# plant: MR6 | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh | exit 0 | echo CLEAN; exit 0
# plant: MR7 | plugin/skills/project-conductor/SKILL.md | echo "SPEC-COPY: DID-NOT-RUN — roadmap marker helper not deployed: mark-roadmap-skipped.sh" | echo "SPEC-COPY: OK — pretend helper deployed"
# plant: MR8 | plugin/skills/project-conductor/SKILL.md | echo "BRANCH-C: DID-NOT-RUN — roadmap marker helper not deployed: mark-roadmap-skipped.sh" | echo "BRANCH-C: OK — pretend helper deployed"
# plant: MR9 | sync-to-claude.sh | plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh|skills/project-conductor/scripts/mark-roadmap-skipped.sh | plugin/skills/project-conductor/scripts/mark-roadmap-skipped-RENAMED.sh|skills/project-conductor/scripts/mark-roadmap-skipped-RENAMED.sh
#
# plant: W1 | plugin/skills/autopilot/SKILL.md | **Five writers**, the last two added by ADR-0111 | **Three writers**, unchanged since ADR-0060
# plant: W3 | plugin/skills/autopilot/SKILL.md | **Branch C is a split, not a downgrade** | **Branch C is relaxed**
# plant: W4 | plugin/scripts/autopilot-guard.sh | v1.4 (2026-08-01, issue #324, ADR-0111) | v1.4 (2026-08-01, unrelated cleanup)
# plant: W5 | plugin/scripts/autopilot-guard.sh | STATE_SUBDIR=".claude/autopilot-state" | STATE_SUBDIR=".claude/autopilot-state"; _unused="skipped-features"
# plant: W6 | plugin/skills/concept-to-code/scripts/manifest-entry-state.sh | run-level halt — was decided by ADR-0111 (issue #324) and is applied by | run-level halt — is deliberately not decided here, and would be applied by
# plant: W7 | plugin/skills/concept-to-code/SKILL.md | ADR-0111 (issue #324), and it is decided in `project-conductor`, not here | issue #324's subject and is deliberately not decided here
# plant: W8 | plugin/skills/project-conductor/SKILL.md | _out=$(bash "$_mes" "$_target" 2>&1); _rc=$? | _out="TERMINAL|assumed"; _rc=0
# plant: W9 | plugin/skills/project-conductor/SKILL.md | is settled HERE (ADR-0111, issue | is a feature-level skip in Step 5C (ADR-0111, issue

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
REPO=$(cd "$STAGING/.." && pwd)

PC="$SKILLS/project-conductor/SKILL.md"
NA="$SKILLS/autopilot/SKILL.md"
C2C="$SKILLS/concept-to-code/SKILL.md"
MES="$SKILLS/concept-to-code/scripts/manifest-entry-state.sh"
GUARD="$STAGING/plugin/scripts/autopilot-guard.sh"
# MRS/SYNCSH — issue #385 (ADR-0132 §D2): mark-roadmap-skipped.sh, the one script the two [~]
# awk programs at lines 435/682 are extracted into. Does not exist yet (tester dispatch); the
# MR section below is expected RED for exactly that reason.
MRS="$SKILLS/project-conductor/scripts/mark-roadmap-skipped.sh"
SYNCSH="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# =====================================================================================
# Shared machinery. Hermetic by construction — every fence runs against a scratch root.

# enumerate_fences <file> — "<opener-line>\t<marker-or-NONE>", indentation-tolerant: two of the
# markers asserted here sit inside numbered list items, and a column-0 anchor would miss them.
enumerate_fences() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) { if (stripped == "```") { infence = 0 } ; next }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

# fence_body <file> <opener-line> — issue #394 / ADR-0133: strips AT MOST the opener's own
# indentation (`ind`), never more than a given line's OWN leading whitespace (`lw`) —
# `strip = (lw < ind) ? lw : ind`. The prior unconditional `substr($0, ind + 1)` corrupted a
# column-0 line inside an indented fence: `conductor-step4-init-guard` is indented 3 and
# `conductor-branch-c-entry-classify` is indented 2, and either D1 wrapper's column-0 `FENCE_BASH`
# terminator extracted as `E_BASH`/`CE_BASH`, no longer the heredoc's own terminator — the rest of
# the fence's body is swallowed into the heredoc and its exit code is destroyed. Both fences' own
# executions in this file stayed GREEN under the bug only because every branch each can take ends in
# an explicit `exit`, so the here-document-to-EOF form terminates before reaching the corrupted line
# — a green-by-accident `required-checks-audit.test.sh`'s `autopilot-check-8` (whose success arm
# falls through instead) exposed. `fence-contract-coverage.test.sh` carries the same fix under the
# same ADR (Task 2); this is a DELIBERATE COPY, not a shared import (ADR-0086: three private
# `fence_body`s already answer this file's own question independently, and each file must fail
# independently).
fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

# extract_fence <file> <id> — anchored on the MARKER, never a heading. ADR-0083 §D3: a heading
# anchor turns a reworded heading into an empty extraction, and an empty script exits 0, so every
# positive assertion goes green while only the abort ones fail. An empty result is a FAILURE here.
extract_fence() {
  _ln=$(enumerate_fences "$1" | grep -F "fence-contract: ${2} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$1" "$_ln"
}

# The substitution contract: a SKILL.md names the DEPLOYED path because that is what the model
# runs; this harness must exercise the STAGING copy, which is what a PR changes.
subst_paths() { sed -e "s|\$HOME/.claude/skills/|$SKILLS/|g" -e "s|~/.claude/skills/|$SKILLS/|g"; }

# run_fence <contract-id> <skill-md> <setup-script> — extract, substitute, prepend the setup that
# binds the fence's free variables, execute, print the exit code. The id is a real argument of a
# real execution, which is what `fence-contract-coverage.test.sh` F4 greps for: a contract is
# covered when something RUNS it, never when a comment says so.
run_fence() {
  _id="$1"; _f="$2"; _setup="$3"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/run-$_id.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  printf '%s\n' "$_body" | subst_paths >>"$_s"
  ( bash "$_s" >"$TMPROOT/out-$_id" 2>&1 ); echo "$?"
}

out_of() { cat "$TMPROOT/out-$1" 2>/dev/null; }

# A real manifest, patched. A hand-written minimal one trips unrelated invariants and reports a
# failure about everything except the thing under test (ADR-0078's lesson). The base is chosen by
# RUNNING the validator over the corpus, not by picking one that looks complete.
BASE_MANIFEST=""; BASE_ROOT=""
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  if bash "$SKILLS/concept-to-code/scripts/manifest-validate.sh" "$_m" >/dev/null 2>&1; then
    BASE_MANIFEST="$_m"
    BASE_ROOT=$(grep '^project_root:' "$_m" | sed -e 's/^project_root:[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    break
  fi
done

# mk_root <name> — a scratch project root. NOT a counter incremented inside $(...): that runs in a
# SUBSHELL, so every call returns the same directory and the fixtures accumulate into each other
# (ADR-0096's `mk_root` bug, met again by the same hand in ADR-0110).
mk_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/docs/manifests" "$_r/docs/specs" "$_r/.claude/autopilot-state"
  printf -- '- [ ] %s\n- [ ] Another feature  (issue #77)\n' "$FEATURE" > "$_r/PROJECT.md"
  printf '%s' "$_r"
}

# mk_manifest <dest> <current_step> <status> — sed-level patching, quoting preserved: the
# validator greps the raw text for a QUOTED absolute path, so a yaml round-trip would be rejected.
mk_manifest() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$(dirname "$(dirname "$1")")|g" \
      -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" "$BASE_MANIFEST" >"$1"
}

SLUG="conductor-split-fixture"
FEATURE='Some feature  (issue #42)'
TODAY=$(date +%Y-%m-%d)

# setup <root> — binds the free variables every fence in this file declares.
setup() {
  # The heredoc terminator (SETUP_EOF) is UNQUOTED, so $STAGING below is expanded by THIS shell
  # before the line is written — same as $1/$SLUG/$FEATURE above it. The single quotes around it
  # are literal output characters, producing a normal single-quoted assignment in setup.sh, never
  # a suppressed expansion. Verified: the generated file carries the real staging path, not the
  # literal text "$STAGING/plugin" (issue #385 dispatch note — flagged for a second look, checked
  # empirically before shipping).
  cat >"$TMPROOT/setup.sh" <<SETUP_EOF
_root='$1'
_slug='$SLUG'
_feature='$FEATURE'
_manifest='${2:-}'
CLAUDE_PLUGIN_ROOT='$STAGING/plugin'
SETUP_EOF
  printf '%s' "$TMPROOT/setup.sh"
}

# =====================================================================================
# A. The three fences exist, are declared, and parse. A declared contract that does not parse is
# the one thing `bash -n` can settle mechanically (ADR-0083 F7).

for _id in conductor-step4-nospec-skip conductor-step4-init-guard conductor-branch-c-entry-classify; do
  _b=$(extract_fence "$PC" "$_id")
  if [ -n "$_b" ]; then
    printf '%s\n' "$_b" > "$TMPROOT/parse-$_id.sh"
    if bash -n "$TMPROOT/parse-$_id.sh" 2>/dev/null; then
      ok "A: $_id is declared and parses"
    else
      bad "A: $_id is declared but does NOT parse as bash"
    fi
  else
    bad "A: $_id is not declared in project-conductor/SKILL.md"
  fi
done

# =====================================================================================
# S. Step 4 — the no-generated-SPEC skip. Cause 2, settled where the evidence is.

# S1: a spec that exists is copied and the fence says proceed. The positive twin: without it, a
# check that fails on everything is indistinguishable from one that works (ADR-0039's correction).
R=$(mk_root s1)
printf '# spec\n' > "$R/docs/specs/42-some-feature.spec.md"
RC=$(run_fence "conductor-step4-nospec-skip" "$PC" "$(setup "$R")")
if [ "$RC" = "0" ] && [ -f "$R/SPEC.md" ] && out_of conductor-step4-nospec-skip | grep -q 'SPEC-COPY: OK'; then
  ok "S1: a resolvable spec is copied to SPEC.md and the fence exits 0"
else
  bad "S1: rc=$RC spec_copied=$( [ -f "$R/SPEC.md" ] && echo yes || echo no ) — $(out_of conductor-step4-nospec-skip | head -2)"
fi

# S2: no spec -> exit 1, a per-feature skip note, and NOT the run-level marker. The whole issue.
R=$(mk_root s2)
RC=$(run_fence "conductor-step4-nospec-skip" "$PC" "$(setup "$R")")
if [ "$RC" = "1" ] && grep -q 'no generated SPEC' "$R/.claude/autopilot-state/skipped-features" 2>/dev/null \
   && [ ! -f "$R/.claude/needs-human" ]; then
  ok "S2: a missing spec is a per-feature skip (exit 1, skip note, no needs-human)"
else
  bad "S2: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo WRITTEN || echo no ) note=$(cat "$R/.claude/autopilot-state/skipped-features" 2>/dev/null | head -1)"
fi

# S3: and the feature is marked [~], so Step 2 does not select it again.
if grep -qF -- "- [~] $FEATURE  (skipped)" "$R/PROJECT.md" 2>/dev/null; then
  ok "S3: the skipped feature is marked [~] in PROJECT.md"
else
  bad "S3: PROJECT.md line not marked [~] — $(grep -n 'issue #42' "$R/PROJECT.md" 2>/dev/null | head -1)"
fi

# S3b: and ONLY that feature. A skip that also rewrites its neighbours is a worse defect than the
# halt it replaces.
if grep -qF -- '- [ ] Another feature  (issue #77)' "$R/PROJECT.md" 2>/dev/null; then
  ok "S3b: the other pending feature is untouched"
else
  bad "S3b: the skip rewrote a line it does not own"
fi

# S4: a feature line with no "(issue #N)" suffix is pre-designed mode — proceed, never skip.
R=$(mk_root s4)
FEATURE_SAVE="$FEATURE"; FEATURE='A pre-designed feature'
printf -- '- [ ] %s\n' "$FEATURE" > "$R/PROJECT.md"
RC=$(run_fence "conductor-step4-nospec-skip" "$PC" "$(setup "$R")")
if [ "$RC" = "0" ] && out_of conductor-step4-nospec-skip | grep -q 'PREDESIGNED' \
   && [ ! -f "$R/.claude/autopilot-state/skipped-features" ]; then
  ok "S4: a feature with no issue suffix is PREDESIGNED and is never skipped"
else
  bad "S4: rc=$RC — $(out_of conductor-step4-nospec-skip | head -1)"
fi
FEATURE="$FEATURE_SAVE"

# S5: no PROJECT.md -> exit 3, DID NOT RUN. Distinct from "nothing to skip" (exit 1), which is the
# distinction #319 was filed about, one level down.
R="$TMPROOT/s5"; mkdir -p "$R/docs/specs" "$R/.claude"
RC=$(run_fence "conductor-step4-nospec-skip" "$PC" "$(setup "$R")")
if [ "$RC" = "3" ] && out_of conductor-step4-nospec-skip | grep -q 'DID-NOT-RUN'; then
  ok "S5: a missing PROJECT.md is exit 3 DID-NOT-RUN, not a silent skip"
else
  bad "S5: rc=$RC — $(out_of conductor-step4-nospec-skip | head -1)"
fi

# =====================================================================================
# G. Step 4 — the entry-init guard. Cause 1's remaining door: the conductor calls
# manifest-init.sh itself, outside concept-to-code step 4b's guard.

# G1: nothing there today -> CREATE, exit 0. The common case; it must stay silent-and-proceed.
R=$(mk_root g1)
RC=$(run_fence "conductor-step4-init-guard" "$PC" "$(setup "$R")")
if [ "$RC" = "0" ] && out_of conductor-step4-init-guard | grep -q 'ENTRY-INIT: CREATE'; then
  ok "G1: no manifest for this slug today -> CREATE, exit 0"
else
  bad "G1: rc=$RC — $(out_of conductor-step4-init-guard | head -1)"
fi

# G2: a Form-C-aborted manifest -> TERMINAL, exit 1. `status: aborted` with `current_step` left
# alone is exactly the live 2026-07-31 orphan, and exactly what a bare `grep current_step` misses.
R=$(mk_root g2)
mk_manifest "$R/docs/manifests/$TODAY-$SLUG.manifest.yml" "step_0_init" "aborted"
RC=$(run_fence "conductor-step4-init-guard" "$PC" "$(setup "$R")")
if [ "$RC" = "1" ] && out_of conductor-step4-init-guard | grep -q 'ENTRY-INIT: TERMINAL'; then
  ok "G2: a status-aborted manifest reads TERMINAL (exit 1), not step_0_init"
else
  bad "G2: rc=$RC — $(out_of conductor-step4-init-guard | head -1)"
fi

# G3: an in-flight manifest -> ADOPT, exit 0, with the instruction NOT to call manifest-init.sh.
# Calling it there is the bare exit 2 this guard exists to stop.
R=$(mk_root g3)
mk_manifest "$R/docs/manifests/$TODAY-$SLUG.manifest.yml" "step_0_init" "in_progress"
RC=$(run_fence "conductor-step4-init-guard" "$PC" "$(setup "$R")")
if [ "$RC" = "0" ] && out_of conductor-step4-init-guard | grep -q 'ENTRY-INIT: ADOPT' \
   && out_of conductor-step4-init-guard | grep -q 'do NOT call manifest-init.sh'; then
  ok "G3: an in-flight manifest reads ADOPT (exit 0) and names the manifest-init.sh trap"
else
  bad "G3: rc=$RC — $(out_of conductor-step4-init-guard | head -2)"
fi

# G4: an unparseable manifest -> exit 2, run-level. Never routed as adoptable.
R=$(mk_root g4)
printf 'not: [valid: yaml\n' > "$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
RC=$(run_fence "conductor-step4-init-guard" "$PC" "$(setup "$R")")
if [ "$RC" = "2" ] && out_of conductor-step4-init-guard | grep -q 'UNREADABLE'; then
  ok "G4: an unparseable manifest is exit 2 (run-level), never adopted"
else
  bad "G4: rc=$RC — $(out_of conductor-step4-init-guard | head -1)"
fi

# G5: no classifier on disk -> exit 3 with the sync remedy. Fails CLOSED, and says which command
# fixes it: an instruction whose remedy names no runnable command is the defect #319 closed.
R=$(mk_root g5)
_b=$(extract_fence "$PC" "conductor-step4-init-guard")
{ cat "$(setup "$R")"; printf '\n'; printf '%s\n' "$_b" | sed 's|\$HOME/.claude/skills/|'"$TMPROOT"'/absent/|g'; } > "$TMPROOT/g5.sh"
bash "$TMPROOT/g5.sh" >"$TMPROOT/out-g5" 2>&1; RC=$?
if [ "$RC" = "3" ] && grep -q 'DID-NOT-RUN' "$TMPROOT/out-g5" && grep -q 'sync-to-claude.sh --apply' "$TMPROOT/out-g5"; then
  ok "G5: a missing classifier is exit 3 and prints the sync remedy"
else
  bad "G5: rc=$RC — $(head -2 "$TMPROOT/out-g5")"
fi

# =====================================================================================
# B. Step 5 branch C — the split itself. R-01 and R-02, both directions.

# B1: TERMINAL -> exit 1, skip note, [~], and NO needs-human. R-01.
R=$(mk_root b1)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
mk_manifest "$MAN" "step_0_init" "aborted"
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "$MAN")")
if [ "$RC" = "1" ] && [ ! -f "$R/.claude/needs-human" ] \
   && grep -q 'terminal state' "$R/.claude/autopilot-state/skipped-features" 2>/dev/null; then
  ok "B1: TERMINAL is a contained per-feature skip (exit 1, note, no needs-human)"
else
  bad "B1: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo WRITTEN || echo no ) — $(out_of conductor-branch-c-entry-classify | head -1)"
fi

# B2: and PROJECT.md carries the [~], so the roadmap advances past it instead of re-selecting it.
if grep -qF -- "- [~] $FEATURE  (skipped)" "$R/PROJECT.md" 2>/dev/null; then
  ok "B2: the skipped feature is marked [~] so Step 2 advances"
else
  bad "B2: PROJECT.md not marked [~]"
fi

# B3: build-status is NOT set RED on a skip. A skip did not stop the roadmap; writing RED would
# poison the next publish through publish-feature.sh even though needs-human is absent.
if [ ! -s "$R/.claude/autopilot-state/build-status" ]; then
  ok "B3: a contained skip leaves build-status alone"
else
  bad "B3: a skip wrote build-status=$(cat "$R/.claude/autopilot-state/build-status")"
fi

# B4: an in-flight (ADOPTABLE) manifest -> exit 2, needs-human. R-02, the other direction. This is
# the shape a crashed coder leaves, and the shape a missing SPEC leaves — neither is a decided end.
R=$(mk_root b4)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
mk_manifest "$MAN" "step_0_init" "in_progress"
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "$MAN")")
if [ "$RC" = "2" ] && grep -q 'did not reach completed' "$R/.claude/needs-human" 2>/dev/null \
   && [ ! -f "$R/.claude/autopilot-state/skipped-features" ]; then
  ok "B4: ADOPTABLE still halts the run (exit 2, needs-human, no skip note)"
else
  bad "B4: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo yes || echo MISSING )"
fi

# B5: and build-status goes RED on a halt — the pre-#324 behaviour, preserved exactly.
if [ "$(cat "$R/.claude/autopilot-state/build-status" 2>/dev/null)" = "RED" ]; then
  ok "B5: a run-level halt still writes build-status RED"
else
  bad "B5: build-status=$(cat "$R/.claude/autopilot-state/build-status" 2>/dev/null) — the halt path regressed"
fi

# B6: a mid-implementation stop -> exit 2. THIS IS THE ADR-0047 §D5 CASE. An anti-test-weakening
# halt never transitions, so the manifest sits at step_5_implementation/in_progress. If someone
# widens the skip path, this is the assertion that goes red, and it must.
R=$(mk_root b6)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
mk_manifest "$MAN" "step_5_implementation" "in_progress"
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "$MAN")")
if [ "$RC" = "2" ] && [ -f "$R/.claude/needs-human" ]; then
  ok "B6: a mid-implementation stop (the weakening-halt shape) stays a run-level halt"
else
  bad "B6: rc=$RC — a weakening halt would now be silently skipped"
fi

# B7: an unparseable manifest -> exit 2. Corruption is not a decided end.
R=$(mk_root b7)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
printf 'not: [valid: yaml\n' > "$MAN"
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "$MAN")")
if [ "$RC" = "2" ] && [ -f "$R/.claude/needs-human" ]; then
  ok "B7: UNREADABLE stays a run-level halt"
else
  bad "B7: rc=$RC"
fi

# B8: no manifest at all, empty _manifest -> the fence constructs today's path, reads NONE, and
# halts. NONE at branch C means the chain never got as far as creating one, which is not contained.
R=$(mk_root b8)
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "")")
if [ "$RC" = "2" ] && [ -f "$R/.claude/needs-human" ]; then
  ok "B8: an empty _manifest resolves to today's path and NONE still halts"
else
  bad "B8: rc=$RC — an absent manifest must not be read as a contained skip"
fi

# B9 / B9b: the two did-not-run paths, and they must be asserted SEPARATELY.
#
# The fence guards "the check did not run" twice — a missing FILE (`[ ! -f "$_mes" ]`) and a
# classifier that ran and failed (`$_rc != 0`) — and a fixture that deletes the file can only ever
# reach the first. The plant registry found this: the B9 plant targeted the `_rc` branch and B9
# went on passing, because the guard above it had already exited. An assertion covered by two
# guards isolates neither (ADR-0104). One fixture per guard.

# B9: no classifier file -> exit 3, and the fence writes NOTHING. An unrun check is not a clean
# result, and it must not fabricate either marker; the caller writes needs-human on this branch.
R=$(mk_root b9)
_b=$(extract_fence "$PC" "conductor-branch-c-entry-classify")
{ cat "$(setup "$R" "")"; printf '\n'; printf '%s\n' "$_b" | sed 's|\$HOME/.claude/skills/|'"$TMPROOT"'/absent/|g'; } > "$TMPROOT/b9.sh"
bash "$TMPROOT/b9.sh" >"$TMPROOT/out-b9" 2>&1; RC=$?
if [ "$RC" = "3" ] && grep -q 'DID-NOT-RUN' "$TMPROOT/out-b9" \
   && [ ! -f "$R/.claude/needs-human" ] && [ ! -f "$R/.claude/autopilot-state/skipped-features" ]; then
  ok "B9: a missing classifier file is exit 3 and writes neither marker"
else
  bad "B9: rc=$RC — $(head -1 "$TMPROOT/out-b9")"
fi

# B9b: a classifier that EXISTS and fails is also exit 3, and is never read as a determination.
# The dangerous shape is the opposite one — treating a failed run as a token and routing on it.
R=$(mk_root b9b)
STUB="$TMPROOT/stub/concept-to-code/scripts"
mkdir -p "$STUB"
printf '#!/bin/bash\necho "boom" >&2\nexit 2\n' > "$STUB/manifest-entry-state.sh"
{ cat "$(setup "$R" "")"; printf '\n'; printf '%s\n' "$_b" | sed 's|\$HOME/.claude/skills/|'"$TMPROOT"'/stub/|g'; } > "$TMPROOT/b9b.sh"
bash "$TMPROOT/b9b.sh" >"$TMPROOT/out-b9b" 2>&1; RC=$?
if [ "$RC" = "3" ] && grep -q 'DID-NOT-RUN' "$TMPROOT/out-b9b" \
   && [ ! -f "$R/.claude/needs-human" ] && [ ! -f "$R/.claude/autopilot-state/skipped-features" ]; then
  ok "B9b: a classifier that runs and fails is exit 3, never routed as a token"
else
  bad "B9b: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo WRITTEN || echo no ) — $(head -1 "$TMPROOT/out-b9b")"
fi

# =====================================================================================
# MR. mark-roadmap-skipped.sh — the two [~] awk programs (lines 435/682) reproduced as one
# script (issue #385, ADR-0132 §D2). This is an ADR-0069-style EXTRACTION, not an ADR-0086
# copy: the two [~] sites are ONE question ("mark this roadmap row skipped"), and two answers
# would be a roadmap disagreeing with itself. These are the FIRST direct tests this program has
# ever had — until now, [~] marking was only ever exercised indirectly, through the whole fence
# (S3/S3b/B2 above).
#
# EXPECTED RED (tester dispatch, issue #385 Task 3). mark-roadmap-skipped.sh does not exist yet.
# Every assertion below fails because the script is missing, or because the two fences still
# inline the awk program rather than resolving and calling it — never because of a defect in
# this test file. NO PLANTS ARE DECLARED HERE: every assertion is red at the end of this
# dispatch, and plant-check.sh cannot distinguish a plant firing from an assertion that was
# already red (ADR-0108/ADR-0115 PC4's own reasoning, applied to the caller side). Declare
# plants once the coder's implementation turns these green.

mrs_root() {
  _d="$TMPROOT/$1"; mkdir -p "$_d"
  printf -- '%s\n' "$2" > "$_d/PROJECT.md"
  printf '%s' "$_d"
}

# MR1: a matching row is marked [~] with the "(skipped)" annotation, verbatim from the two
# existing awk programs, and the script exits 0 ("ran and produced a result" — ADR-0132 §D4).
MR1_FEAT='Some feature  (issue #42)'
R=$(mrs_root mr1 "- [ ] $MR1_FEAT")
bash "$MRS" "$R/PROJECT.md" "$MR1_FEAT" >"$TMPROOT/out-mr1" 2>&1
RC=$?
if [ "$RC" = "0" ] && grep -qF -- "- [~] $MR1_FEAT  (skipped)" "$R/PROJECT.md"; then
  ok "MR1: mark-roadmap-skipped.sh marks a matching row [~] (skipped) and exits 0"
else
  bad "MR1: rc=$RC — $(head -1 "$R/PROJECT.md" 2>/dev/null) — $(head -1 "$TMPROOT/out-mr1" 2>/dev/null)"
fi

# MR2: a non-matching feature title leaves PROJECT.md BYTE-IDENTICAL. Exit 0 either way — the
# script's own contract is "ran", never "matched" (ADR-0132 §D4: 0 = ran whether or not a row
# matched).
R=$(mrs_root mr2 "- [ ] $MR1_FEAT")
cp "$R/PROJECT.md" "$TMPROOT/mr2-before"
bash "$MRS" "$R/PROJECT.md" 'A completely different feature  (issue #99)' >"$TMPROOT/out-mr2" 2>&1
RC=$?
if [ "$RC" = "0" ] && cmp -s "$TMPROOT/mr2-before" "$R/PROJECT.md"; then
  ok "MR2: a non-matching feature title leaves PROJECT.md byte-identical (exit 0)"
else
  bad "MR2: rc=$RC — PROJECT.md changed on a non-matching title, or exit code was not 0"
fi

# MR3: a title carrying sed metacharacters ([ . * /) is matched by EXACT WHOLE-LINE comparison,
# never a regex — both existing call sites carry a comment saying exactly this, and a feature
# title is arbitrary GitHub text that can carry any sed metacharacter or delimiter.
MR3_FEAT='Ship a[b].c*d/e  (issue #7)'
R=$(mrs_root mr3 "- [ ] $MR3_FEAT")
bash "$MRS" "$R/PROJECT.md" "$MR3_FEAT" >"$TMPROOT/out-mr3" 2>&1
RC=$?
if [ "$RC" = "0" ] && grep -qF -- "- [~] $MR3_FEAT  (skipped)" "$R/PROJECT.md"; then
  ok "MR3: a title carrying [ . * / is matched by exact whole-line comparison, never a regex"
else
  bad "MR3: rc=$RC — a sed-metacharacter title was not marked — $(head -1 "$R/PROJECT.md" 2>/dev/null)"
fi

# MR4 — bad invocation (ADR-0132 §D4: 2 = bad invocation). A missing required argument is the
# unambiguous case; the script cannot mark anything without a feature title to compare against.
R=$(mrs_root mr4 "- [ ] $MR1_FEAT")
bash "$MRS" "$R/PROJECT.md" >"$TMPROOT/out-mr4" 2>&1
RC=$?
if [ "$RC" = "2" ]; then
  ok "MR4: invoking mark-roadmap-skipped.sh with a missing feature-title argument exits 2 (bad invocation)"
else
  bad "MR4: rc=$RC, expected 2 for a missing-argument invocation — $(head -1 "$TMPROOT/out-mr4" 2>/dev/null)"
fi

# MR5 — could not run (ADR-0132 §D4: 3 = could not run). A project-md path that does not exist
# cannot be read or written; distinct from MR2's "ran, found nothing to mark".
bash "$MRS" "$TMPROOT/mr5-does-not-exist/PROJECT.md" "$MR1_FEAT" >"$TMPROOT/out-mr5" 2>&1
RC=$?
if [ "$RC" = "3" ]; then
  ok "MR5: a project-md path that does not exist exits 3 (could not run), not 2 or a silent no-op"
else
  bad "MR5: rc=$RC, expected 3 for an unreadable/missing PROJECT.md — $(head -1 "$TMPROOT/out-mr5" 2>/dev/null)"
fi

# MR6 — no CLEAN sentinel, ever (ADR-0132 §D4: this script is not a reporter). Checked across
# every captured output above.
if ! grep -qi 'CLEAN' "$TMPROOT"/out-mr[1-5] 2>/dev/null; then
  ok "MR6: mark-roadmap-skipped.sh never prints a CLEAN sentinel across any of the cases above"
else
  bad "MR6: mark-roadmap-skipped.sh printed CLEAN somewhere — it must never grow a reporter sentinel (ADR-0132 §D4)"
fi

# MR7/MR8 — both fences take their EXISTING DID-NOT-RUN exit-3 branch when mark-roadmap-skipped.sh
# is unresolvable. The renamed-filename substitution targets the LITERAL PATH SUBSTRING the
# two-tier resolution will use (the h16-direction-check.sh pattern already used two call sites
# below, at project-conductor/SKILL.md's Step 5 H16 block), so it correctly finds nothing to
# break TODAY (the fences still inline the awk program) and correctly breaks BOTH tiers once the
# coder adds the two-tier resolution, regardless of which tier is checked first.

# MR7: conductor-step4-nospec-skip, on the SKIP path (no generated SPEC — same fixture as S2).
R=$(mk_root mr7)
_b=$(extract_fence "$PC" "conductor-step4-nospec-skip")
_b_broken=$(printf '%s\n' "$_b" | sed 's|project-conductor/scripts/mark-roadmap-skipped\.sh|project-conductor/scripts/DOES-NOT-EXIST-mark-roadmap-skipped.sh|g')
{ cat "$(setup "$R")"; printf '\n'; printf '%s\n' "$_b_broken" | subst_paths; } > "$TMPROOT/mr7.sh"
bash "$TMPROOT/mr7.sh" >"$TMPROOT/out-mr7" 2>&1
RC=$?
if [ "$RC" = "3" ] && grep -q 'SPEC-COPY: DID-NOT-RUN' "$TMPROOT/out-mr7" \
   && grep -q 'sync-to-claude.sh --apply' "$TMPROOT/out-mr7"; then
  ok "MR7: conductor-step4-nospec-skip takes the existing DID-NOT-RUN exit-3 branch when mark-roadmap-skipped.sh is unresolvable"
else
  bad "MR7: rc=$RC — $(head -2 "$TMPROOT/out-mr7" 2>/dev/null | tr '\n' ' ') — still inlines the awk program, or does not yet resolve the helper two-tier"
fi

# MR8: conductor-branch-c-entry-classify, on the TERMINAL path (same fixture as B1).
R=$(mk_root mr8)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
mk_manifest "$MAN" "step_0_init" "aborted"
_bc=$(extract_fence "$PC" "conductor-branch-c-entry-classify")
_bc_broken=$(printf '%s\n' "$_bc" | sed 's|project-conductor/scripts/mark-roadmap-skipped\.sh|project-conductor/scripts/DOES-NOT-EXIST-mark-roadmap-skipped.sh|g')
{ cat "$(setup "$R" "$MAN")"; printf '\n'; printf '%s\n' "$_bc_broken" | subst_paths; } > "$TMPROOT/mr8.sh"
bash "$TMPROOT/mr8.sh" >"$TMPROOT/out-mr8" 2>&1
RC=$?
if [ "$RC" = "3" ] && grep -q 'BRANCH-C: DID-NOT-RUN' "$TMPROOT/out-mr8" \
   && grep -q 'sync-to-claude.sh --apply' "$TMPROOT/out-mr8"; then
  ok "MR8: conductor-branch-c-entry-classify takes the existing DID-NOT-RUN exit-3 branch when mark-roadmap-skipped.sh is unresolvable on the TERMINAL path"
else
  bad "MR8: rc=$RC — $(head -2 "$TMPROOT/out-mr8" 2>/dev/null | tr '\n' ' ') — still inlines the awk program, or does not yet resolve the helper two-tier"
fi

# MR9 — the PAIRS entry. pairs-completeness.test.sh cannot see a skill scripts/ file (its
# check_complete covers plugin/skills with */SKILL.md only — ADR-0043), so this is the only guard
# (ADR-0109 MES0b / ADR-0069 PTB7 precedent).
if grep -qF 'plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh|skills/project-conductor/scripts/mark-roadmap-skipped.sh' "$SYNCSH"; then
  ok "MR9: the PAIRS entry for mark-roadmap-skipped.sh exists in sync-to-claude.sh"
else
  bad "MR9: no PAIRS entry for mark-roadmap-skipped.sh in sync-to-claude.sh"
fi

# =====================================================================================
# CDA. Task 6 (issue #385, ADR-0132 §D2/§D4/§D5): conductor-args.sh, replacing Step 0's `$1`
# autopilot check and its `"$@"`/--fork-from scan (SKILL.md 39-56) with real positional parameters
# — legal inside a script, illegal inside a rendered fence. Prints two lines: `autopilot=<true|
# false>` and `fork_from=<ref-or-empty>`. This is the ONE call site in this feature that changes
# RENDERED behaviour on purpose: today `$1` is filled by the substituter while `$@`/`$#` are the
# EXECUTING SHELL's (empty), so neither parse has ever worked as written.
#
# EXPECTED RED (tester dispatch, issue #385 Task 6). conductor-args.sh does not exist yet, so
# CDA1-CDA5 fail on a missing file (bash: …: No such file or directory, rc=127); CDA6 (the PAIRS
# entry) fails because nothing has been added to sync-to-claude.sh yet; CDA7 fails via
# EXTRACT_FAILED because the coder has not yet added `<!-- fence-contract: conductor-step0-args
# -->` to project-conductor/SKILL.md — never because of a defect in this test. NO PLANTS ARE
# DECLARED HERE, for the same reason Section MR states: a separate tester pass declares them once
# the coder's implementation turns these green.
#
# CDA7 is also this file's contribution to ADR-0083 §F4 (fence-contract-coverage.test.sh): F4
# accepts the literal source string `run_fence "<id>"` as proof of execution, independent of
# whether the call currently succeeds — so the string below is what keeps F3/F4/F6/F7/F9 green
# once the coder's marker lands, verified by re-running that file in this same dispatch (its own
# baseline: PASS=45 FAIL=0, unaffected today since "conductor-step0-args" is not yet a declared id).
#
# PLANTS (issue #385 dispatch, Batch 3 test-authoring pass — conductor-args.sh is green now).
# CDA1/CDA3 target the two `_autopilot` sites (the match condition and the default, respectively)
# so a broken match and a broken default are distinguishable failures. CDA2/CDA4 both sit inside
# the same --fork-from value-capture line and are kept apart deliberately: CDA2 mutates the index
# ADVANCE taken only when a value actually follows the flag (so a value-present run captures the
# wrong slot), CDA4 mutates only the FALLBACK a positional parameter takes when nothing follows it
# (so an absent value stops defaulting to empty) — neither mutation touches the other's case. CDA5
# reproduces the exact bug its own comment names: the match condition made to depend on
# `_autopilot`, so the flag scan stops being independent of the first token's value, which is
# precisely what CDA5 exists to catch (and CDA2's fixture, whose first token IS "autopilot", is
# unaffected by it — verified). CDA6 mirrors MR9's own PAIRS-entry technique two sections above.
# CDA7 removes DID-NOT-RUN from the fence's own not-deployed message — the one thing its grep
# depends on that rc=3 alone does not prove; it cannot touch the resolvable-path positive control,
# which never reaches that branch.
# plant: CDA1 | plugin/skills/project-conductor/scripts/conductor-args.sh | [ "${1:-}" = "autopilot" ] && _autopilot=true | [ "${1:-}" = "autopilot-typo" ] && _autopilot=true
# plant: CDA2 | plugin/skills/project-conductor/scripts/conductor-args.sh | _i=$((_i+1)); eval | _i=$((_i+2)); eval
# plant: CDA3 | plugin/skills/project-conductor/scripts/conductor-args.sh | _autopilot=false | _autopilot=true
# plant: CDA4 | plugin/skills/project-conductor/scripts/conductor-args.sh | _fork_from=\${$_i:-} | _fork_from=\${$_i:-CDA4CRASH}
# plant: CDA5 | plugin/skills/project-conductor/scripts/conductor-args.sh | [ "$_a" = "--fork-from" ] && { | [ "$_a" = "--fork-from" ] && [ "$_autopilot" = "true" ] && {
# plant: CDA6 | sync-to-claude.sh | plugin/skills/project-conductor/scripts/conductor-args.sh|skills/project-conductor/scripts/conductor-args.sh | plugin/skills/project-conductor/scripts/conductor-args-RENAMED.sh|skills/project-conductor/scripts/conductor-args-RENAMED.sh
# plant: CDA7 | plugin/skills/project-conductor/SKILL.md | CONDUCTOR-ARGS: DID-NOT-RUN — argument parser not deployed | CONDUCTOR-ARGS: argument parser not deployed

CAS="$SKILLS/project-conductor/scripts/conductor-args.sh"

# setup_cda <args> — binds the one free variable the fence declares (_args, the raw argument
# string, exactly the `autopilot` §1.3 Phase S pattern this ADR points at) plus CLAUDE_PLUGIN_ROOT,
# bound to the STAGING copy for the same reason setup()/setup_ar() already bind it in this and the
# sibling file: an unbound CLAUDE_PLUGIN_ROOT falls through to $HOME/.claude and can make an
# assertion pass from the deployed copy instead of staging/ (this session's own RJ14 finding).
setup_cda() {
  cat >"$TMPROOT/setup-cda.sh" <<SETUP_EOF
_args='$1'
CLAUDE_PLUGIN_ROOT='$STAGING/plugin'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-cda.sh"
}

# CDA1: a bare "autopilot" -> autopilot=true, fork_from empty, exit 0.
OUT=$(bash "$CAS" autopilot 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'autopilot=true' \
   && printf '%s\n' "$OUT" | grep -qxF 'fork_from='; then
  ok "CDA1: a bare 'autopilot' first token -> autopilot=true, fork_from empty"
else
  bad "CDA1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CDA2: "autopilot --fork-from main" -> autopilot=true, fork_from=main.
OUT=$(bash "$CAS" autopilot --fork-from main 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'autopilot=true' \
   && printf '%s\n' "$OUT" | grep -qxF 'fork_from=main'; then
  ok "CDA2: 'autopilot --fork-from main' -> autopilot=true, fork_from=main"
else
  bad "CDA2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CDA3: no arguments at all -> autopilot=false, fork_from empty (today's attended-mode default,
# byte-identical per ADR-0132 §D2's "Empty in attended mode" sentence, unmoved).
OUT=$(bash "$CAS" 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'autopilot=false' \
   && printf '%s\n' "$OUT" | grep -qxF 'fork_from='; then
  ok "CDA3: no arguments -> autopilot=false, fork_from empty"
else
  bad "CDA3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CDA4: "--fork-from" with nothing after it (the only/last token) -> fork_from stays empty rather
# than crashing on a reference past the argument list; not an autopilot token either.
OUT=$(bash "$CAS" --fork-from 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'autopilot=false' \
   && printf '%s\n' "$OUT" | grep -qxF 'fork_from='; then
  ok "CDA4: --fork-from with nothing after it -> fork_from stays empty, exit 0 (no crash)"
else
  bad "CDA4: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CDA5: a first token that is not "autopilot" -> autopilot=false, and --fork-from is still scanned
# for independently of the first token's value.
OUT=$(bash "$CAS" notautopilot --fork-from feat/x 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'autopilot=false' \
   && printf '%s\n' "$OUT" | grep -qxF 'fork_from=feat/x'; then
  ok "CDA5: a first token that is not 'autopilot' -> autopilot=false, fork_from still scanned for"
else
  bad "CDA5: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CDA6 -- the PAIRS entry. pairs-completeness.test.sh cannot see a skill scripts/ file (its
# check_complete covers plugin/skills with */SKILL.md only -- ADR-0043), so this is the only guard
# (ADR-0109 MES0b / ADR-0069 PTB7 / MR9 precedent, same file).
if grep -qF 'plugin/skills/project-conductor/scripts/conductor-args.sh|skills/project-conductor/scripts/conductor-args.sh' "$SYNCSH"; then
  ok "CDA6: the PAIRS entry for conductor-args.sh exists in sync-to-claude.sh"
else
  bad "CDA6: no PAIRS entry for conductor-args.sh in sync-to-claude.sh"
fi

# CDA7: Step 0's fence takes an exit-3 CONDUCTOR-ARGS: DID-NOT-RUN branch, with the sync remedy
# printed, when conductor-args.sh is unresolvable — there is NO safe default on this fence
# (ADR-0132 §D2/§D4: false prompts with nobody present, true runs unattended when nobody asked).
#
# RETARGETED (issue #385 dispatch, Batch 3 test-authoring pass). The marker now exists
# (project-conductor/SKILL.md:51) and Task 6 vendored conductor-args.sh onto staging, so the
# ORIGINAL fixture — a plain `run_fence` call with nothing renamed — resolves on the FIRST tier
# (CLAUDE_PLUGIN_ROOT) and returns rc=0: the assertion as first written could never reach the
# branch it names, because it never made the helper unresolvable. Verified live both ways before
# writing this.
#
# The plain call stays, unlike MR7/MR8's full replacement, and is executed as a genuine positive
# control: it is also this file's literal contribution to fence-contract-coverage.test.sh F4,
# which greps *.test.sh for the exact string `run_fence "<id>"` as proof of execution (see this
# file's own header) — this is the ONLY call site for the "conductor-step0-args" id (CDA1-CDA6
# call conductor-args.sh directly, not through the fence), so dropping it would silently redden a
# file this dispatch's own baseline reports GREEN (PASS=45 FAIL=0). A second, RENAMED extraction —
# the same technique MR7/MR8 already use, two sections above — is what actually exercises the
# unresolvable branch: it substitutes the helper path INSIDE the extracted fence body, before
# subst_paths() runs, to a name that cannot exist on either tier (subst_paths rewrites the
# `$HOME/.claude/skills/` tier onto the SAME staging directory CLAUDE_PLUGIN_ROOT already points
# at, so only a renamed substring — not an environment override — can break both at once).
# The fence's SUCCESS path is silent by design: it only sets the internal `_autopilot`/
# `_fork_from` variables for the steps below it to read (CDA1-CDA5 test those parses directly
# against conductor-args.sh, not through the fence). So the positive control below asserts rc=0
# with no DID-NOT-RUN output — the fence's own stdout contract on the resolvable path — never a
# printed `autopilot=` line, which this block does not emit.
RC0=$(run_fence "conductor-step0-args" "$PC" "$(setup_cda "autopilot")")
OUT0=$(out_of conductor-step0-args)
_b0=$(extract_fence "$PC" "conductor-step0-args")
_b0_broken=$(printf '%s\n' "$_b0" | sed 's|project-conductor/scripts/conductor-args\.sh|project-conductor/scripts/DOES-NOT-EXIST-conductor-args.sh|g')
{ cat "$(setup_cda "autopilot")"; printf '\n'; printf '%s\n' "$_b0_broken" | subst_paths; } > "$TMPROOT/cda7.sh"
bash "$TMPROOT/cda7.sh" >"$TMPROOT/out-cda7" 2>&1
RC=$?
OUT=$(cat "$TMPROOT/out-cda7" 2>/dev/null)
if [ "$RC0" = "0" ] && [ -z "$OUT0" ] \
   && [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'CONDUCTOR-ARGS: DID-NOT-RUN' \
   && printf '%s' "$OUT" | grep -q 'sync-to-claude.sh --apply'; then
  ok "CDA7: Step 0's fence resolves conductor-args.sh when it is deployed (rc=0, silent), and takes the CONDUCTOR-ARGS: DID-NOT-RUN branch (exit 3, sync remedy) when it is not"
else
  bad "CDA7: resolvable rc=$RC0 out=$(printf '%s' "$OUT0" | head -1) — unresolvable rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# =====================================================================================
# W. The writer list and the deferral notes. Static, and every needle targets a MECHANISM or a
# distinctive clause rather than the name of the thing it asserts about (rule 12 — five instances
# in one day in this repository, every one an assertion whose needle was the subject's own name).

# flat <file> — line breaks, backticks and asterisks removed. A clause is the same clause whether
# it wraps, whether a word inside it is code-quoted, and whether it is bolded
# (ADR-0073 / ADR-0076 / ADR-0080 / ADR-0098, four members of the same family).
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr -d '`*'; }
flat "$NA" > "$TMPROOT/na.flat"
flat "$PC" > "$TMPROOT/pc.flat"

# W1: §3.3 names five writers, not three. The list is prose that enumerates its writers; leaving
# it at three is two files disagreeing with no way to tell which is authoritative (ADR-0042).
if grep -q 'Five writers' "$TMPROOT/na.flat"; then
  ok "W1: autopilot §3.3 states five skipped-features writers"
else
  bad "W1: §3.3 still claims a different writer count — $(grep -o '[A-Za-z]* writers' "$TMPROOT/na.flat" | head -1)"
fi

# W2: and it names both new ones, so the count and the enumeration cannot drift apart.
if grep -q 'no-generated-SPEC skip' "$TMPROOT/na.flat" && grep -q 'entry-state skip' "$TMPROOT/na.flat"; then
  ok "W2: §3.3 enumerates both conductor writers by name"
else
  bad "W2: §3.3 raised the count without naming the writers"
fi

# W3: §3.3 says the split is bounded — only a decided end skips. Without this sentence the section
# reads as a general downgrade of branch C, which is what B6 exists to prevent in code.
if grep -q 'split, not a downgrade' "$TMPROOT/na.flat"; then
  ok "W3: §3.3 bounds the split (only TERMINAL takes the skip path)"
else
  bad "W3: §3.3 does not bound the split"
fi

# W4: autopilot-guard.sh's header moved with the writers it points at. It is the file that tells the
# next author where a new skip writer goes; a stale list there sends them to needs-human.
if grep -q 'issue #324' "$GUARD" && grep -q 'branch C' "$GUARD"; then
  ok "W4: autopilot-guard.sh's marker-contract header names the new writers"
else
  bad "W4: autopilot-guard.sh's header still describes the pre-#324 writer set"
fi

# W5: the guard still reads only needs-human. This feature adds writers to a file the guard must
# go on ignoring; if it ever started reading skipped-features, every skip would halt the run.
if ! grep -q 'skipped-features"' "$GUARD" && ! grep -q 'skipped_features' "$GUARD"; then
  ok "W5: autopilot-guard.sh still never reads skipped-features"
else
  bad "W5: autopilot-guard.sh now reads the per-feature note — every skip would halt the run"
fi

# W6/W7: the two sites that deferred this decision must no longer say it is open. Both sent this
# investigation to the right place; leaving them stale sends the next one to a closed question —
# the rot CLAUDE.md records for ADR-0016. Needles target the CLAIM, not the issue number, which
# both files legitimately keep.
if ! grep -q 'deliberately not decided here' "$MES" && grep -q 'ADR-0111' "$MES"; then
  ok "W6: manifest-entry-state.sh's header records the decision instead of deferring it"
else
  bad "W6: manifest-entry-state.sh still says the policy is undecided"
fi
flat "$C2C" > "$TMPROOT/c2c.flat"
if ! grep -q 'deliberately not decided here' "$TMPROOT/c2c.flat" \
   && grep -q 'ADR-0111' "$TMPROOT/c2c.flat" \
   && grep -q 'decided in project-conductor, not here' "$TMPROOT/c2c.flat"; then
  ok "W7: concept-to-code step 4b records the decision and points at the conductor"
else
  bad "W7: concept-to-code step 4b still defers the policy, or does not name where it now lives"
fi

# W8: branch C no longer writes needs-human unconditionally. The needle is the INVOCATION
# (`bash "$_mes"`), never the script's name: `manifest-entry-state.sh` also appears in the `_mes=`
# assignment, so a needle on the name stays satisfied after the call is deleted. That is rule 12
# in the assertion written to guard against it — caught by planting, not by reading.
_bc=$(extract_fence "$PC" "conductor-branch-c-entry-classify")
if printf '%s\n' "$_bc" | grep -qF 'bash "$_mes"' \
   && printf '%s\n' "$_bc" | grep -q 'TERMINAL)'; then
  ok "W8: branch C classifies before deciding (the classifier is INVOKED and the TERMINAL arm exists)"
else
  bad "W8: branch C's fence does not invoke the classifier, or has no TERMINAL arm — the split is gone"
fi

# W9: the no-spec block no longer routes the decision to Step 5C. That sentence pointed at a
# branch with no mechanism to act on it, and M4 shows the chain does not hard-abort there either.
if ! grep -q 'feature-level skip in Step 5C' "$TMPROOT/pc.flat"; then
  ok "W9: the stale 'treat that as a feature-level skip in Step 5C' routing is gone"
else
  bad "W9: Step 4 still defers the missing-SPEC case to a branch that cannot act on it"
fi

# =====================================================================================
# ==================================================================================================
# FK. Fork point and the run ledger (issue #364, ADR-0127 §D4).
#
# PROJECT.md is marked [x] ON THE FEATURE BRANCH and never on the base the next feature forks from,
# so the checkbox for a feature that just published still reads [ ] to the conductor. Forking from
# main therefore re-picks it for ever; forking from the previous tip stacks every PR. The run's own
# append-only ledger decides instead, and the fork point is the run-scoped prep branch.
#
# FK2-FK5 EXECUTE the fence. A prose assertion would pass on a fence that documents the ledger and
# never reads it.
# ==================================================================================================
COND="$STAGING/plugin/skills/project-conductor/SKILL.md"
AUTOSK="$STAGING/plugin/skills/autopilot/SKILL.md"
DISARM="$SCRIPTS/autopilot-disarm.sh"
FK_FENCE=$(awk '/fence-contract: conductor-published-skip -->/{f=1;next} f&&/^```bash/{g=1;next} g&&/^```/{exit} g' "$COND")

if [ -z "$FK_FENCE" ]; then
  bad "FK1: the conductor-published-skip fence extracted nothing — an empty extraction is a FAILURE, never a skip"
else
  _fkd=$(mktemp -d "${TMPDIR:-/tmp}/fk.XXXXXX")
  printf '%s\n' "$FK_FENCE" > "$_fkd/f.sh"
  bash -n "$_fkd/f.sh" 2>/dev/null && ok "FK1: the published-skip fence parses as bash (ADR-0083 F7)" \
    || bad "FK1: the published-skip fence does not parse"
  _fk() { ( export _root="$1" _slug="$2" _autopilot="$3"; bash "$_fkd/f.sh" >/dev/null 2>&1; printf '%s' "$?" ) ; }

  mkdir -p "$_fkd/a/.claude/autopilot-state"; printf '102-req-ids\n' > "$_fkd/a/.claude/autopilot-state/published"
  mkdir -p "$_fkd/b/.claude/autopilot-state"

# plant: FK2 | plugin/skills/project-conductor/SKILL.md | elif grep -qxF "$_slug" "$_led" 2>/dev/null; then | elif false; then
  [ "$(_fk "$_fkd/a" 102-req-ids true)" = "1" ] \
    && ok "FK2: a slug already in the ledger returns ALREADY (exit 1) — the conductor cannot re-pick a feature that published in this run" \
    || bad "FK2: an already-published slug did not return exit 1 — the roadmap would re-pick the feature that just finished, for ever"

  [ "$(_fk "$_fkd/a" 103-other true)" = "0" ] \
    && ok "FK3: a slug not in the ledger returns PENDING (exit 0)" \
    || bad "FK3: an unpublished slug did not return exit 0"

  [ "$(_fk "$_fkd/a" 102-req-ids-coverage true)" = "0" ] \
    && ok "FK4: matching is whole-line — a slug that is a PREFIX of a published one does not collide" \
    || bad "FK4: '102-req-ids-coverage' collided with published '102-req-ids' — the match is not whole-line"

# plant: FK5 | plugin/skills/project-conductor/SKILL.md | elif [ ! -e "$_led" ]; then | elif false; then
  [ "$(_fk "$_fkd/b" 102-req-ids true)" = "0" ] \
    && ok "FK5: an ABSENT ledger returns 0 (nothing published yet) and is distinct from an unreadable one" \
    || bad "FK5: an absent ledger did not return 0 — 'no feature has published yet' is the common legitimate case and must not read as an error"

  # An unreadable ledger must be exit 3, never confused with an empty one. Skipped when the test
  # user can read a chmod-000 file (CI often runs as root — ADR-0028's caveat), because there the
  # fixture cannot express the state at all and a pass would be for the wrong reason.
  mkdir -p "$_fkd/c/.claude/autopilot-state"; printf 'x\n' > "$_fkd/c/.claude/autopilot-state/published"
  chmod 000 "$_fkd/c/.claude/autopilot-state/published" 2>/dev/null
  if [ -r "$_fkd/c/.claude/autopilot-state/published" ]; then
    ok "FK6 (skipped, not asserted): this user can read a chmod-000 file, so the unreadable-ledger state is not expressible here"
  else
    [ "$(_fk "$_fkd/c" 102-req-ids true)" = "3" ] \
      && ok "FK6: an UNREADABLE ledger returns 3 (did not run), never 0 — a run that cannot tell what it published must stop rather than re-pick" \
      || bad "FK6: an unreadable ledger did not return 3"
  fi
  chmod 644 "$_fkd/c/.claude/autopilot-state/published" 2>/dev/null
fi

FP_FENCE=$(awk '/fence-contract: conductor-fork-point -->/{f=1;next} f&&/^```bash/{g=1;next} g&&/^```/{exit} g' "$COND")
if [ -z "$FP_FENCE" ]; then
  bad "FK11: the conductor-fork-point fence extracted nothing — an empty extraction is a FAILURE, never a skip"
else
  _fpd=$(mktemp -d "${TMPDIR:-/tmp}/fp.XXXXXX")
  printf '%s\n' "$FP_FENCE" > "$_fpd/f.sh"
  bash -n "$_fpd/f.sh" 2>/dev/null && ok "FK11: the fork-point fence parses as bash" \
    || bad "FK11: the fork-point fence does not parse"
  _mkr() { d="$_fpd/$1"; mkdir -p "$d"; git -C "$d" init -q -b main >/dev/null 2>&1
    git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i >/dev/null 2>&1; printf '%s' "$d"; }
  _fp() { ( export _root="$1" _fork_from="$2"; bash "$_fpd/f.sh" >/dev/null 2>&1
      printf '%s|%s' "$?" "$(git -C "$1" branch --show-current)" ) ; }

# plant: FK12 | plugin/skills/project-conductor/SKILL.md | git -C "$_root" checkout -q "$_fork_from" 2>/dev/null | true
  _r=$(_mkr a); git -C "$_r" branch autopilot/prep-x >/dev/null 2>&1; git -C "$_r" checkout -q -b feat/first >/dev/null 2>&1
  [ "$(_fp "$_r" autopilot/prep-x)" = "0|autopilot/prep-x" ] \
    && ok "FK12: from the PREVIOUS feature's tip the fence moves onto the prep ref — this is what stops PR N containing features 1..N" \
    || bad "FK12: the fence did not move off the previous feature's tip; every feature branch would stack on the last one"

  _r=$(_mkr b)
  [ "$(_fp "$_r" autopilot/prep-missing)" = "3|main" ] \
    && ok "FK13: a fork ref that does not resolve is DID-NOT-RUN (exit 3), never a silent fall back to HEAD" \
    || bad "FK13: an unresolvable fork ref did not return 3 — the run would fork from wherever HEAD happened to be and look correct"

# plant: FK14 | plugin/skills/project-conductor/SKILL.md | elif [ -n "$(git -C "$_root" status --porcelain 2>/dev/null)" ]; then | elif false; then
  _r=$(_mkr c); git -C "$_r" branch autopilot/prep-x >/dev/null 2>&1; printf 'x' > "$_r/dirty.txt"
  [ "$(_fp "$_r" autopilot/prep-x)" = "2|main" ] \
    && ok "FK14: a dirty tree refuses the base switch (exit 2) rather than carrying uncommitted work across branches" \
    || bad "FK14: a dirty tree did not refuse the base switch"

  _r=$(_mkr d)
  [ "$(_fp "$_r" "")" = "0|main" ] \
    && ok "FK15 (unchanged-behaviour guard): with no --fork-from the fence is INACTIVE and HEAD is used as-is" \
    || bad "FK15: the fence acted without --fork-from — the attended flow must be byte-identical"
fi

# plant: FK7 | plugin/skills/project-conductor/SKILL.md | printf '%s\n' "<topic-slug>" >> "$_root/.claude/autopilot-state/published" | true
if grep -qF 'autopilot-state/published' "$COND" && grep -qF '>> "$_root/.claude/autopilot-state/published"' "$COND"; then
  ok "FK7: the publish block APPENDS to the ledger — the producer the FK2 check consumes"
else
  bad "FK7: nothing writes .claude/autopilot-state/published — the skip check would read an empty ledger for ever (the producer/consumer defect this repo has recorded six times)"
fi

# plant: FK8 | plugin/skills/autopilot/SKILL.md | Prep branch — commit Phase P's outputs | Prep branch — assorted notes
if grep -qF "Prep branch — commit Phase P's outputs" "$AUTOSK"; then
  ok "FK8: Phase P has a step that commits its outputs onto the run-scoped prep branch"
else
  bad "FK8: Phase P does not commit its outputs — every SPEC it writes would live only on whichever feature branch commits first (VCS-003, observed 2026-08-04)"
fi

# plant: FK9 | plugin/skills/autopilot/SKILL.md | args="autopilot --fork-from | args="autopilot
if grep -qF 'args="autopilot --fork-from' "$AUTOSK"; then
  ok "FK9: the conductor is handed the prep ref to fork from"
else
  bad "FK9: no fork point is passed to the conductor — feature N+1 forks from wherever HEAD happens to be"
fi

# FK10 was "the disarm clears the run ledger" (issue #364, ADR-0127 §D4); inverted by issue #400,
# ADR-0167 §D1 — disarm no longer clears `published`, it preserves it and reports so, and the old
# needle `"$SDIR/published"` collided with BOTH the presence-check and the read of that same file
# in the new preserved-reporting block (CI caught this live: plant-shard (2) reported FK10 as a
# malformed plant, needle matched 2 times instead of 1). Re-anchored to the unique `preserved:`
# report line, which exists nowhere else in the file.
# plant: FK10 | plugin/scripts/autopilot-disarm.sh | preserved: $STATE_SUBDIR/published | noted: $STATE_SUBDIR/published
if grep -qF 'preserved: $STATE_SUBDIR/published' "$DISARM"; then
  ok "FK10: disarm PRESERVES the run ledger (published) rather than clearing it — reset, if any, is decided at the next launch, never here (ADR-0167 §D1/§D4)"
else
  bad "FK10: autopilot-disarm.sh no longer reports published as preserved — a silent regression back to clearing it would skip every feature the prior run shipped"
fi

# Z1: assertion-count floor. A floor, not an exact count: it catches an assertion that VANISHES
# (ADR-0083 §D3 — a suite reporting fewer assertions does not read as broken, and nobody watches
# the number) without needing a bump on every addition. Raised 57 -> 64 (issue #385 Task 6): the
# seven new CDA assertions above, ALL SEVEN counted toward PASS+FAIL regardless of their RED/GREEN
# colour, because `TOTAL` sums executed assertions, not passing ones — a failing assertion still
# ran (the seven CDA cases are exactly that: expected-red today, still counted).
TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -ge 64 ]; then
  ok "Z1: assertion floor met ($TOTAL)"
else
  bad "Z1: only $TOTAL assertions executed, expected >= 64 — did an extraction return empty?"
fi

echo "----"
echo "conductor-entry-failure-split.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
