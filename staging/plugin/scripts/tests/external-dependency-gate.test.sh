#!/bin/bash
# external-dependency-gate.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash external-dependency-gate.test.sh
#
# Covers issue #114 / ADR-0060: G13, the external-dependency feasibility gate, and the marker
# split (§D3) that fixes a pre-existing latent defect in autopilot-guard.sh's needs-human handling.
#
# `E`-prefixed section labels are new to this file's own two-letter form (EA-EH). secret-dep-gate
# .test.sh already uses single-letter `E1..E12` for an unrelated section (dependency-scan.sh); the
# two-letter `EA/EB/...` labels used here do not collide with any existing test file (checked by
# grep across all 36 pre-existing harnesses before this file was written).
#
# NO FIXTURE PATH IN THIS FILE CONTAINS "secret" (singular or plural), "credential", ".env",
# ".pem", or ".key" — protect-files.sh denies any path containing "secrets", and this feature is
# about credentials, so names are picked carefully (ADR-0060 issue brief).
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
GATE="$SCRIPTS/external-dependency-check.sh"
GUARD="$SCRIPTS/autopilot-guard.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TAB=$(printf '\t')

mkroot() { r="$TMP/$1"; mkdir -p "$r/.claude/autopilot-state"; printf '%s' "$r"; }

# ==============================================================================================
# EA — the plan template and architect.md carry the external-dependency declaration (§D1).
# ==============================================================================================
ARCH="$STAGING/plugin/agents/architect.md"

if [ -f "$ARCH" ]; then
  ok "EA0: architect.md is where this harness expects it (the anchor EA1-EA4 read)"
else
  bad "EA0: $ARCH not found — EA1-EA4 below are meaningless"
fi

if grep -qi 'External-dependency declaration' "$ARCH" 2>/dev/null && grep -q 'ADR-0060' "$ARCH" 2>/dev/null; then
  ok "EA1: architect.md carries an External-dependency declaration bullet citing ADR-0060"
else
  bad "EA1: architect.md has no External-dependency declaration bullet citing ADR-0060"
fi

if grep -q 'EXTERNAL DEPENDENCY:' "$ARCH" 2>/dev/null; then
  ok "EA2: architect.md documents the EXTERNAL DEPENDENCY: line format"
else
  bad "EA2: architect.md does not document the EXTERNAL DEPENDENCY: line format"
fi

if grep -q 'ADR-0053' "$ARCH" 2>/dev/null && grep -q 'ADR-0055' "$ARCH" 2>/dev/null; then
  ARCH_EDEP_BLOCK=$(awk '/External-dependency declaration/{f=1} f{print} f&&/^- \*\*/&&!/External-dependency declaration/{if(c++)exit}' "$ARCH")
  if printf '%s' "$ARCH_EDEP_BLOCK" | grep -q 'ADR-0053' && printf '%s' "$ARCH_EDEP_BLOCK" | grep -q 'ADR-0055'; then
    ok "EA3: the declaration bullet cites the propose-never-write-silently contract (ADR-0053 §D6 / ADR-0055 §D5)"
  else
    bad "EA3: architect.md mentions ADR-0053/ADR-0055 but not inside the declaration bullet itself"
  fi
else
  bad "EA3: architect.md does not cite both ADR-0053 and ADR-0055 near the declaration bullet"
fi

C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
if [ -f "$C2C" ] && grep -q 'EXTERNAL DEPENDENCY:' "$C2C" 2>/dev/null; then
  ok "EA4: concept-to-code/SKILL.md's Step 2 consumes the EXTERNAL DEPENDENCY: convention"
else
  bad "EA4: concept-to-code/SKILL.md does not reference EXTERNAL DEPENDENCY: lines"
fi

# ==============================================================================================
# EB — the gate checks PRESENT-TENSE PROVISIONING STATE, not provisionability, and refuses to
# dispatch unattended on an unmet declared dependency (§D2).
# ==============================================================================================
if [ -x "$GATE" ] || [ -f "$GATE" ]; then
  ok "EB0: external-dependency-check.sh exists (the anchor EB1-EB6 read)"
else
  bad "EB0: $GATE not found — EB1-EB6 below are meaningless"
fi

OUT=""; RC=0
run_gate() { OUT=$(printf '%s' "$1" | bash "$GATE" 2>"$TMP/gerr"); RC=$?; }

run_gate 'EXTERNAL DEPENDENCY: Stripe | payment API | provisioned: true'
[ "$RC" -eq 0 ] && ok "EB1: a provisioned:true dependency passes (exit 0)" \
  || bad "EB1: expected exit 0, got rc=$RC out=$OUT"

run_gate 'EXTERNAL DEPENDENCY: Stripe | payment API | provisioned: false'
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "^UNMET${TAB}Stripe${TAB}payment API${TAB}false\$"; then
  ok "EB2: a provisioned:false dependency refuses (exit 1) and names it"
else
  bad "EB2: expected exit 1 + UNMET Stripe line — got rc=$RC out=$OUT"
fi

run_gate 'EXTERNAL DEPENDENCY: GoogleOAuth | consent screen | provisioned: unknown'
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "^UNMET${TAB}GoogleOAuth${TAB}consent screen${TAB}unknown\$"; then
  ok "EB3: provisioned:unknown is treated as NOT provisioned — default strict (SPEC edge case)"
else
  bad "EB3: expected exit 1 + UNMET GoogleOAuth line — got rc=$RC out=$OUT"
fi

run_gate 'EXTERNAL DEPENDENCY: Stripe | payment API | provisioned: false'
if grep -qi 'human action' "$TMP/gerr" && ! grep -qi '\bretry\b.*again\|try again' "$TMP/gerr"; then
  ok "EB4: the refusal names a human action on stderr, framed as never a retry"
else
  bad "EB4: stderr does not name a human action — got: $(cat "$TMP/gerr" 2>/dev/null)"
fi

run_gate 'EXTERNAL DEPENDENCY: Zeta | z | provisioned: false
EXTERNAL DEPENDENCY: Alpha | a | provisioned: false'
EB5_WANT=$(printf 'UNMET\tAlpha\ta\tfalse\nUNMET\tZeta\tz\tfalse')
if [ "$OUT" = "$EB5_WANT" ]; then
  ok "EB5: multiple unmet dependencies are reported sorted and deterministic"
else
  bad "EB5: expected sorted Alpha-then-Zeta — got: $OUT"
fi

OUT2=$(bash "$GATE" --nonsense </dev/null 2>"$TMP/gerr2"); RC2=$?
[ "$RC2" -eq 2 ] && [ -s "$TMP/gerr2" ] && ok "EB6: an unknown flag exits 2 with usage on stderr" \
  || bad "EB6: expected exit 2 + stderr, got rc=$RC2"

# ==============================================================================================
# EC — the per-feature skip does NOT halt the roadmap (§D3, the most important section here). A
# skip note is distinct from the run-level needs-human marker, and autopilot-guard.sh halts on the
# latter and not the former.
# ==============================================================================================
if [ -x "$GUARD" ] || [ -f "$GUARD" ]; then
  ok "EC0: autopilot-guard.sh exists (the anchor EC1-EC3 read)"
else
  bad "EC0: $GUARD not found — EC1-EC3 below are meaningless"
fi

R=$(mkroot ec1)
printf 'issue #9 "Thin issue" skipped: body too short\n' > "$R/.claude/autopilot-state/skipped-features"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "EC1: a per-feature skip note alone does not halt the guard" \
  || bad "EC1: guard halted on a skip-note-only root — the marker split is not in place"

R=$(mkroot ec2)
printf 'issue #9 "Thin issue" skipped: body too short\n' > "$R/.claude/autopilot-state/skipped-features"
: > "$R/.claude/autopilot-state/build-status"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "EC2: a skip note next to an otherwise-clean root still allows publish" \
  || bad "EC2: guard halted with only a skip note present and a clean build-status"

R=$(mkroot ec3)
: > "$R/.claude/autopilot-state/skipped-features"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "EC3: an empty skip-note file does not halt (structural sanity)" \
  || bad "EC3: guard halted on an empty skip-note file"

# ==============================================================================================
# ED — the existing thin-issue writer (spec-from-issue Step 2) and #113's injection-suspect
# writer (spec-from-issue Step 1.5) are MOVED onto the per-feature note, and a regression
# assertion proves a thin issue no longer halts a multi-feature run.
# ==============================================================================================
SFI="$STAGING/plugin/skills/spec-from-issue/SKILL.md"
if [ -f "$SFI" ]; then
  ok "ED0: spec-from-issue/SKILL.md is where this harness expects it (the anchor ED1-ED4 read)"
else
  bad "ED0: $SFI not found — ED1-ED4 below are meaningless"
fi

if grep -q 'autopilot-state/skipped-features' "$SFI" 2>/dev/null; then
  ok "ED1: spec-from-issue/SKILL.md references the per-feature skip-note path"
else
  bad "ED1: spec-from-issue/SKILL.md does not reference autopilot-state/skipped-features"
fi

# ED2 — the two writer lines themselves must target the new path, not needs-human.
SFI_WRITERS=$(grep -c '>> "<root>/.claude/needs-human"' "$SFI" 2>/dev/null); SFI_WRITERS=${SFI_WRITERS:-0}
SFI_NEWWRITERS=$(grep -c 'autopilot-state/skipped-features"' "$SFI" 2>/dev/null); SFI_NEWWRITERS=${SFI_NEWWRITERS:-0}
if [ "$SFI_WRITERS" -eq 0 ] && [ "$SFI_NEWWRITERS" -ge 2 ]; then
  ok "ED2: both spec-from-issue writers (thin-issue, injection-suspect) target the per-feature note, none target needs-human"
else
  bad "ED2: expected 0 needs-human writers and >=2 skipped-features writers — got needs-human=$SFI_WRITERS skipped-features=$SFI_NEWWRITERS"
fi

if grep -qi 'injection-shaped content detected' "$SFI" 2>/dev/null; then
  ok "ED3: the injection-suspect skip text is still present (moved, not deleted)"
else
  bad "ED3: injection-suspect skip text is missing from spec-from-issue/SKILL.md"
fi

# ED4 — regression proof: a thin-issue-shaped skip note for feature A must not block feature B's
# publish. This is the exact defect ADR-0060 §D3 describes: "one thin issue in a twenty-feature
# roadmap silently halts the other nineteen."
R=$(mkroot ed4)
printf 'issue #3 "Too thin" skipped: body too short (80 < 120 non-space chars)\n' \
  > "$R/.claude/autopilot-state/skipped-features"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "ED4: a thin-issue skip note does not halt a later feature's publish (the #114 regression proof)" \
  || bad "ED4: a thin-issue-shaped skip note halted the guard — the defect is not fixed"

# ==============================================================================================
# EE — REGRESSION GUARD. The run-level halts still fire unchanged for red build, RTF blocker and
# budget breach, since Task 4 edits the guard that owns them. This matters more than the new
# feature (plan risk flag #1) — every assertion below must stay green across this whole feature.
# ==============================================================================================
R=$(mkroot ee_clean)
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "EE0: a clean root still allows (forward guard)" || bad "EE0: clean root no longer allows"

R=$(mkroot ee_red); printf 'RED' > "$R/.claude/autopilot-state/build-status"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "EE1: RED build still halts (regression guard)" || bad "EE1: RED build no longer halts"

R=$(mkroot ee_nh); printf 'feature X failed mid-flight, unknown state' > "$R/.claude/needs-human"
out=$("$GUARD" --check "$R" 2>/dev/null); rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'feature X failed mid-flight'; } \
  && ok "EE2: a genuine run-level needs-human marker still halts with its reason (regression guard)" \
  || bad "EE2: run-level needs-human no longer halts — THIS IS THE CORE REGRESSION RISK"

R=$(mkroot ee_rtf); printf 'BLOCKER: auth bypass' > "$R/.claude/autopilot-state/rtf-blocker"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "EE3: rtf-blocker still halts (regression guard)" || bad "EE3: rtf-blocker no longer halts"

R=$(mkroot ee_budg); printf 'limit=1000\nspent=1200\n' > "$R/.claude/autopilot-state/token-budget"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "EE4: token budget exceeded still halts (regression guard)" || bad "EE4: budget breach no longer halts"

# EE5 — a needs-human marker halts EVEN WHEN a skip note is also present (the two files must be
# read independently — the skip note must never mask a genuine run-level halt).
R=$(mkroot ee_both)
printf 'issue #9 "Thin issue" skipped: body too short\n' > "$R/.claude/autopilot-state/skipped-features"
printf 'unknown-state failure' > "$R/.claude/needs-human"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "EE5: needs-human still halts even alongside an unrelated skip note" \
  || bad "EE5: a skip note masked a genuine run-level halt — CRITICAL regression"

# ==============================================================================================
# EF — absent declaration is inert (§D5): the text states it means "nobody said", not "none
# exist" — the gate cannot tell the difference and must not imply it can.
# ==============================================================================================
run_gate ''
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "EF1: empty input is inert — exit 0, no output" \
  || bad "EF1: expected silent exit 0 on empty input, got rc=$RC out=$OUT"

run_gate 'This plan has no external dependencies. Nothing to declare here.'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "EF2: prose with no EXTERNAL DEPENDENCY: line is inert" \
  || bad "EF2: expected silent exit 0 on dependency-free prose, got rc=$RC out=$OUT"

if grep -qi 'nobody said' "$ARCH" 2>/dev/null; then
  ok "EF3: architect.md states absence means \"nobody said\", not \"none exist\""
else
  bad "EF3: architect.md does not state the §D5 absent-means-nobody-said distinction"
fi

# ==============================================================================================
# EG — the gate runs at BOTH c2c Gate 2 and autopilot Phase P from one implementation (§D4): the
# same script name is referenced from both skill files, not reimplemented per call site.
# ==============================================================================================
AUTOPILOT_SKILL="$STAGING/plugin/skills/autopilot/SKILL.md"
if [ -f "$AUTOPILOT_SKILL" ]; then
  ok "EG0: autopilot/SKILL.md is where this harness expects it (the anchor EG1-EG2 read)"
else
  bad "EG0: $AUTOPILOT_SKILL not found — EG1-EG2 below are meaningless"
fi

if grep -q 'external-dependency-check.sh' "$C2C" 2>/dev/null; then
  ok "EG1: concept-to-code/SKILL.md invokes external-dependency-check.sh"
else
  bad "EG1: concept-to-code/SKILL.md does not reference external-dependency-check.sh"
fi

if grep -q 'external-dependency-check.sh' "$AUTOPILOT_SKILL" 2>/dev/null; then
  ok "EG2: autopilot/SKILL.md invokes the SAME external-dependency-check.sh (one implementation, two call sites)"
else
  bad "EG2: autopilot/SKILL.md does not reference external-dependency-check.sh"
fi

if grep -q 'ADR-0060' "$AUTOPILOT_SKILL" 2>/dev/null; then
  ok "EG3: autopilot/SKILL.md cites ADR-0060"
else
  bad "EG3: autopilot/SKILL.md does not cite ADR-0060"
fi

# ==============================================================================================
# EH — registration in both CI registries (ci.yml glob automatic; docs-ci.yml explicit named
# list needs a manual append after untrusted-input). Same G-section pattern as
# secret-dep-gate.test.sh: this section lives INSIDE the harness it registers.
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"

if [ -f "$DOCSCI" ]; then
  ok "EH0a: docs-ci.yml is where this harness expects it"
else
  bad "EH0a: $DOCSCI not found — EH1 below is meaningless"
fi
if [ -f "$SYNCSH" ]; then
  ok "EH0b: sync-to-claude.sh is where this harness expects it"
else
  bad "EH0b: $SYNCSH not found — EH2/EH3 below are meaningless"
fi

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]external-dependency-gate[[:space:];]'; then
  ok "EH1: docs-ci.yml's shell-tests loop list runs external-dependency-gate"
else
  bad "EH1: external-dependency-gate is not in docs-ci.yml's explicit harness list — append it after untrusted-input"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"
if grep -qxF 'plugin/scripts/external-dependency-check.sh|hooks/external-dependency-check.sh' "$TMP/pairs"; then
  ok "EH2: PAIRS deploys external-dependency-check.sh to ~/.claude/hooks/"
else
  bad "EH2: no PAIRS entry for external-dependency-check.sh — edits will never deploy"
fi

if grep -q 'external-dependency-gate' "$TMP/pairs"; then
  bad "EH3: PAIRS gained an entry for the harness itself — it validates staging/ and runs in this repo's CI, no deploy"
else
  ok "EH3: no PAIRS entry for the harness itself (matches every harness added since ADR-0041)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
