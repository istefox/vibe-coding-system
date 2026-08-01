#!/bin/bash
# conductor-entry-failure-split.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash conductor-entry-failure-split.test.sh
#
# THE RULE — `project-conductor` must not answer "this feature did not complete" with "the run
# cannot be trusted". A KNOWN, CONTAINED, per-feature entry failure appends to
# `.claude/nightly-state/skipped-features`, marks the feature `[~]`, and the roadmap continues; a
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
# plant: S2 | plugin/skills/project-conductor/SKILL.md | "$_issue" "$_feature" "$_issue" >> "$_root/.claude/nightly-state/skipped-features" | "$_issue" "$_feature" "$_issue" > "$_root/.claude/needs-human"
# plant: S3 | plugin/skills/project-conductor/SKILL.md | can carry any sed metacharacter or delimiter. awk -v f="$_feature" | can carry any sed metacharacter or delimiter. awk -v f="NOMATCH"
# plant: G2 | plugin/skills/project-conductor/SKILL.md | ENTRY-INIT: TERMINAL (${_out#*|}) | ENTRY-INIT: ADOPT (${_out#*|})
# plant: G5 | plugin/skills/project-conductor/SKILL.md | echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply" exit 3 fi # Constructed here | exit 3 fi # Constructed here
# plant: B1 | plugin/skills/project-conductor/SKILL.md | "$_feature" "${_out#*|}" >> "$_root/.claude/nightly-state/skipped-features" | "$_feature" "${_out#*|}" > "$_root/.claude/needs-human"
# plant: B4 | plugin/skills/project-conductor/SKILL.md | "$_feature" "$_out" > "$_root/.claude/needs-human" | "$_feature" "$_out" >> "$_root/.claude/nightly-state/skipped-features"
# plant: B6 | plugin/skills/project-conductor/SKILL.md | case "${_out%%|*}" in TERMINAL) | case "${_out%%|*}" in TERMINAL|RESUMABLE|ADOPTABLE)
# plant: B9 | plugin/skills/project-conductor/SKILL.md | echo "BRANCH-C: DID-NOT-RUN — classifier missing: $_mes" | printf 'x' > "$_root/.claude/needs-human"; echo "BRANCH-C: DID-NOT-RUN — classifier missing: $_mes"
# plant: B9b | plugin/skills/project-conductor/SKILL.md | [ "$_rc" -eq 0 ] || { echo "BRANCH-C: DID-NOT-RUN — $_out"; exit 3; } | [ "$_rc" -eq 0 ] || { _out="TERMINAL|guessed"; }
# plant: W1 | plugin/skills/nightly-autopilot/SKILL.md | **Five writers**, the last two added by ADR-0111 | **Three writers**, unchanged since ADR-0060
# plant: W3 | plugin/skills/nightly-autopilot/SKILL.md | **Branch C is a split, not a downgrade** | **Branch C is relaxed**
# plant: W4 | plugin/scripts/nightly-guard.sh | v1.4 (2026-08-01, issue #324, ADR-0111) | v1.4 (2026-08-01, unrelated cleanup)
# plant: W5 | plugin/scripts/nightly-guard.sh | STATE_SUBDIR=".claude/nightly-state" | STATE_SUBDIR=".claude/nightly-state"; _unused="skipped-features"
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
NA="$SKILLS/nightly-autopilot/SKILL.md"
C2C="$SKILLS/concept-to-code/SKILL.md"
MES="$SKILLS/concept-to-code/scripts/manifest-entry-state.sh"
GUARD="$STAGING/plugin/scripts/nightly-guard.sh"

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

fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      print substr($0, ind + 1)
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
  mkdir -p "$_r/docs/manifests" "$_r/docs/specs" "$_r/.claude/nightly-state"
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
  cat >"$TMPROOT/setup.sh" <<SETUP_EOF
_root='$1'
_slug='$SLUG'
_feature='$FEATURE'
_manifest='${2:-}'
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
if [ "$RC" = "1" ] && grep -q 'no generated SPEC' "$R/.claude/nightly-state/skipped-features" 2>/dev/null \
   && [ ! -f "$R/.claude/needs-human" ]; then
  ok "S2: a missing spec is a per-feature skip (exit 1, skip note, no needs-human)"
else
  bad "S2: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo WRITTEN || echo no ) note=$(cat "$R/.claude/nightly-state/skipped-features" 2>/dev/null | head -1)"
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
   && [ ! -f "$R/.claude/nightly-state/skipped-features" ]; then
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
   && grep -q 'terminal state' "$R/.claude/nightly-state/skipped-features" 2>/dev/null; then
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
if [ ! -s "$R/.claude/nightly-state/build-status" ]; then
  ok "B3: a contained skip leaves build-status alone"
else
  bad "B3: a skip wrote build-status=$(cat "$R/.claude/nightly-state/build-status")"
fi

# B4: an in-flight (ADOPTABLE) manifest -> exit 2, needs-human. R-02, the other direction. This is
# the shape a crashed coder leaves, and the shape a missing SPEC leaves — neither is a decided end.
R=$(mk_root b4)
MAN="$R/docs/manifests/$TODAY-$SLUG.manifest.yml"
mk_manifest "$MAN" "step_0_init" "in_progress"
RC=$(run_fence "conductor-branch-c-entry-classify" "$PC" "$(setup "$R" "$MAN")")
if [ "$RC" = "2" ] && grep -q 'did not reach completed' "$R/.claude/needs-human" 2>/dev/null \
   && [ ! -f "$R/.claude/nightly-state/skipped-features" ]; then
  ok "B4: ADOPTABLE still halts the run (exit 2, needs-human, no skip note)"
else
  bad "B4: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo yes || echo MISSING )"
fi

# B5: and build-status goes RED on a halt — the pre-#324 behaviour, preserved exactly.
if [ "$(cat "$R/.claude/nightly-state/build-status" 2>/dev/null)" = "RED" ]; then
  ok "B5: a run-level halt still writes build-status RED"
else
  bad "B5: build-status=$(cat "$R/.claude/nightly-state/build-status" 2>/dev/null) — the halt path regressed"
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
   && [ ! -f "$R/.claude/needs-human" ] && [ ! -f "$R/.claude/nightly-state/skipped-features" ]; then
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
   && [ ! -f "$R/.claude/needs-human" ] && [ ! -f "$R/.claude/nightly-state/skipped-features" ]; then
  ok "B9b: a classifier that runs and fails is exit 3, never routed as a token"
else
  bad "B9b: rc=$RC needs_human=$( [ -f "$R/.claude/needs-human" ] && echo WRITTEN || echo no ) — $(head -1 "$TMPROOT/out-b9b")"
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
  ok "W1: nightly-autopilot §3.3 states five skipped-features writers"
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

# W4: nightly-guard.sh's header moved with the writers it points at. It is the file that tells the
# next author where a new skip writer goes; a stale list there sends them to needs-human.
if grep -q 'issue #324' "$GUARD" && grep -q 'branch C' "$GUARD"; then
  ok "W4: nightly-guard.sh's marker-contract header names the new writers"
else
  bad "W4: nightly-guard.sh's header still describes the pre-#324 writer set"
fi

# W5: the guard still reads only needs-human. This feature adds writers to a file the guard must
# go on ignoring; if it ever started reading skipped-features, every skip would halt the run.
if ! grep -q 'skipped-features"' "$GUARD" && ! grep -q 'skipped_features' "$GUARD"; then
  ok "W5: nightly-guard.sh still never reads skipped-features"
else
  bad "W5: nightly-guard.sh now reads the per-feature note — every skip would halt the run"
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
# Z1: assertion-count floor. A floor, not an exact count: it catches an assertion that VANISHES
# (ADR-0083 §D3 — a suite reporting fewer assertions does not read as broken, and nobody watches
# the number) without needing a bump on every addition.
TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -ge 26 ]; then
  ok "Z1: assertion floor met ($TOTAL)"
else
  bad "Z1: only $TOTAL assertions executed, expected >= 26 — did an extraction return empty?"
fi

echo "----"
echo "conductor-entry-failure-split.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
