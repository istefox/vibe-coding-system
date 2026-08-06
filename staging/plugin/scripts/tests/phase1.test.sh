#!/bin/bash
# Phase 1 test harness (ADR-0022) — autopilot-guard + publish-feature (offline, no network).
# Bash 3.2 clean. Run: bash phase1.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$SCRIPTS/autopilot-guard.sh"
PUBLISH="$SCRIPTS/publish-feature.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
# `FAIL: ` with the colon is not cosmetic — plant-check.sh attributes a fired plant with
# `grep "^FAIL: <id>"`, so a harness printing `FAIL <label>` is one where every plant reports
# "did not fire" whether the assertion held or collapsed (issue #370, ADR-0128 §D4). Four sibling
# harnesses still print the colon-less form and none of them declares a plant; plant-check.sh now
# refuses a plant in such a file rather than mis-reporting it.
no()   { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# assert_exit <expected> <label> -- reads actual exit from $? captured by caller
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkroot() { r="$tmp/$1"; mkdir -p "$r/.claude/autopilot-state"; printf '%s' "$r"; }

# --- autopilot-guard --check ---
R=$(mkroot clean)
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guard: clean root allows" || no "guard: clean root allows"

R=$(mkroot red); printf 'RED' > "$R/.claude/autopilot-state/build-status"
out=$("$GUARD" --check "$R" 2>/dev/null); rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'AUTOPILOT-GUARD HALT'; } \
  && ok "guard: RED build halts" || no "guard: RED build halts"

R=$(mkroot nh); printf 'missing logo asset' > "$R/.claude/needs-human"
out=$("$GUARD" --check "$R" 2>/dev/null); rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'missing logo asset'; } \
  && ok "guard: needs-human halts with reason" || no "guard: needs-human halts with reason"

R=$(mkroot rtf); printf 'BLOCKER: auth bypass' > "$R/.claude/autopilot-state/rtf-blocker"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: rtf-blocker halts" || no "guard: rtf-blocker halts"

R=$(mkroot budg); printf 'limit=1000\nspent=1200\n' > "$R/.claude/autopilot-state/token-budget"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: budget exceeded halts" || no "guard: budget exceeded halts"

R=$(mkroot budg2); printf 'limit=1000\nspent=500\n' > "$R/.claude/autopilot-state/token-budget"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guard: budget under limit allows" || no "guard: budget under limit allows"

"$GUARD" --check "/no/such/dir/xyz" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: invalid root fail-safe blocks" || no "guard: invalid root fail-safe blocks"

# --- autopilot-guard hook mode ---
if command -v jq >/dev/null 2>&1; then
  R=$(mkroot hookclean)
  echo "{\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: non-publish command inert" || no "guard hook: non-publish command inert"

  echo "{\"tool_input\":{\"command\":\"git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: publish without active marker inert" || no "guard hook: publish without active marker inert"

  touch "$R/.claude/autopilot-state/active"
  printf 'RED' > "$R/.claude/autopilot-state/build-status"
  echo "{\"tool_input\":{\"command\":\"gh pr create --base main\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: active + RED blocks publish" || no "guard hook: active + RED blocks publish"

  rm -f "$R/.claude/autopilot-state/build-status"
  echo "{\"tool_input\":{\"command\":\"git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: active + clean allows publish" || no "guard hook: active + clean allows publish"

  # Forbidden publishes during an autopilot run must be blocked (review finding #1).
  echo "{\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks push to main" || no "guard hook: blocks push to main"

  echo "{\"tool_input\":{\"command\":\"git push origin HEAD:master\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks push HEAD:master" || no "guard hook: blocks push HEAD:master"

  echo "{\"tool_input\":{\"command\":\"gh pr merge 123 --merge --auto\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks gh pr merge" || no "guard hook: blocks gh pr merge"

  echo "{\"tool_input\":{\"command\":\"git push --force origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks force push" || no "guard hook: blocks force push"

  # A feature-branch push must still be allowed (no false positive on 'main' inside a slug).
  echo "{\"tool_input\":{\"command\":\"git push -u origin feat/domain-model\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: allows feat/ push containing 'main' substring" || no "guard hook: allows feat/ push containing 'main' substring"

  # v1.2 (audit 1.3): +<ref> force-refspecs are force-pushes and must be blocked.
  echo "{\"tool_input\":{\"command\":\"git push origin +main\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks push origin +main" || no "guard hook: blocks push origin +main"

  echo "{\"tool_input\":{\"command\":\"git push origin +master\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks push origin +master" || no "guard hook: blocks push origin +master"

  echo "{\"tool_input\":{\"command\":\"git push origin +refs/heads/feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks +refs/heads force refspec" || no "guard hook: blocks +refs/heads force refspec"

  # v1.2 (audit 2.12): --no-verify is never allowed unattended.
  echo "{\"tool_input\":{\"command\":\"git push --no-verify -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks push --no-verify" || no "guard hook: blocks push --no-verify"

  # v1.2: --force-with-lease is still a force-push.
  echo "{\"tool_input\":{\"command\":\"git push --force-with-lease origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: blocks --force-with-lease" || no "guard hook: blocks --force-with-lease"

  # v1.2 (audit 3.22): an unrelated -f in a composite must not block a clean publish.
  echo "{\"tool_input\":{\"command\":\"rm -f build.log && git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: allows composite with unrelated rm -f" || no "guard hook: allows composite with unrelated rm -f"

  # v1.2: a +token before the push segment (date +%s) must not read as a force refspec.
  echo "{\"tool_input\":{\"command\":\"date +%s && git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: allows composite with date +%s" || no "guard hook: allows composite with date +%s"

  # v1.2 (audit 2.11): malformed JSON fails closed on a forbidden publish, open otherwise.
  printf '{"tool_input":{"command":"git push --force origin main"' | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: malformed JSON + forbidden publish blocks" || no "guard hook: malformed JSON + forbidden publish blocks"

  printf '{"tool_input":{"command":"ls -la"' | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: malformed JSON + harmless command allows" || no "guard hook: malformed JSON + harmless command allows"
else
  printf 'skip guard hook tests (no jq)\n'
fi

# --- publish-feature (dry-run, offline) ---
R=$(mkroot pub)
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init && git remote add origin https://example.invalid/x.git )

"$PUBLISH" --slug demo --root "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "publish: missing opt-in marker refuses" || no "publish: missing opt-in marker refuses"

printf 'publish: true\n' > "$R/.claude/autopilot.yml"
out=$("$PUBLISH" --slug demo --root "$R" --dry-run 2>&1); rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'AUTOPILOT-PUBLISH demo'; } \
  && ok "publish: opt-in + dry-run prints status line" || no "publish: opt-in + dry-run prints status line"

printf '%s' "$out" | grep -q -- '--force' && no "publish: dry-run must not use --force" || ok "publish: no --force in dry-run"

"$PUBLISH" --slug main --root "$R" --dry-run >/dev/null 2>&1
[ $? -eq 2 ] && ok "publish: slug=main refused" || no "publish: slug=main refused"

# guard integration: RED build blocks publish even with opt-in
printf 'RED' > "$R/.claude/autopilot-state/build-status"
"$PUBLISH" --slug demo --root "$R" --dry-run >/dev/null 2>&1
[ $? -eq 2 ] && ok "publish: guard HALT aborts publish" || no "publish: guard HALT aborts publish"

# --- CR: the PR closing reference (issue #370, ADR-0128) ---
# Before this, publish-feature.sh built the PR body as a fixed inline string, so an unattended run
# opened a PR that closed nothing and the feature's issue stayed open after the merge. PR #362 /
# issue #292 is the observed instance: the body had to be edited by hand.
CRR=$(mkroot pubclose)
( cd "$CRR" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init && git remote add origin https://example.invalid/x.git )
printf 'publish: true\n' > "$CRR/.claude/autopilot.yml"

# The dry run must PRINT the body, or nothing below can reach it. This is the mechanism CR1-CR3
# rest on, so it is asserted on its own rather than assumed by them.
# plant: CR1 | plugin/scripts/publish-feature.sh | printf 'publish-feature: [dry-run] PR body:\n%s\n' "$PR_BODY" >&2 | true
crout=$("$PUBLISH" --slug demo --root "$CRR" --dry-run 2>&1)
printf '%s\n' "$crout" | grep -q 'dry-run..*PR body' \
  && ok "CR1 dry-run prints the PR body" || no "CR1 dry-run prints the PR body"

# The body goes to stderr because stdout carries the AUTOPILOT-PUBLISH line the /goal evaluator and
# the morning report parse. A body on stdout would corrupt both, and would do it silently.
# plant: CR2 | plugin/scripts/publish-feature.sh | "$PR_BODY" >&2 | "$PR_BODY"
crstdout=$("$PUBLISH" --slug demo --root "$CRR" --dry-run 2>/dev/null)
printf '%s\n' "$crstdout" | grep -q 'PR body' \
  && no "CR2 the body stays off stdout" || ok "CR2 the body stays off stdout"

# plant: CR3 | plugin/scripts/publish-feature.sh | Closes #$ISSUE | Refs #$ISSUE
crout=$("$PUBLISH" --slug demo --issue 292 --root "$CRR" --dry-run 2>&1)
printf '%s\n' "$crout" | grep -q '^Closes #292$' \
  && ok "CR3 --issue N puts 'Closes #N' in the body, on its own line" \
  || no "CR3 --issue N puts 'Closes #N' in the body, on its own line"

# GitHub honours a closing keyword only outside a list item or a code fence, so the blank line
# before it is load-bearing, not formatting.
printf '%s\n' "$crout" | grep -B1 '^Closes #292$' | head -1 | grep -qE '^[[:space:]]*$' \
  && ok "CR4 the closing reference is preceded by a blank line" \
  || no "CR4 the closing reference is preceded by a blank line"

# No --issue must leave the body exactly as it was before the flag existed. A roadmap not generated
# from issues has no number, and that case stays silent rather than warning.
crout=$("$PUBLISH" --slug demo --root "$CRR" --dry-run 2>&1)
printf '%s\n' "$crout" | grep -q 'Closes #' \
  && no "CR5 no --issue emits no closing reference" || ok "CR5 no --issue emits no closing reference"

# An EMPTY --issue must behave as absent. project-conductor passes the flag unconditionally rather
# than through `${_issue:+...}`, because that idiom relies on word splitting and this shell may be
# zsh, where an unquoted expansion does not split (issue #366) — flag and value would arrive as one
# argument. Empty is therefore a defined, reachable input, not an edge case.
crout=$("$PUBLISH" --slug demo --issue "" --root "$CRR" --dry-run 2>&1)
{ printf '%s\n' "$crout" | grep -q 'AUTOPILOT-PUBLISH demo' \
  && ! printf '%s\n' "$crout" | grep -q 'Closes #'; } \
  && ok "CR6 an empty --issue behaves as absent" || no "CR6 an empty --issue behaves as absent"

# plant: CR7 | plugin/scripts/publish-feature.sh | fail "--issue must be digits only, got: $ISSUE" | ISSUE=""
"$PUBLISH" --slug demo --issue "292; rm -rf /" --root "$CRR" --dry-run >/dev/null 2>&1
[ $? -eq 2 ] && ok "CR7 a malformed --issue is refused" || no "CR7 a malformed --issue is refused"

# CR4, CR5 and CR6 carry NO declared plant, and the reasons differ — an undeclared omission reads
# as an oversight, which is worse than the gap.
#   CR4 — removing the blank line before the reference needs a replacement CONTAINING a newline,
#         which registry v1 cannot express (ADR-0112). Not a weak assertion, an unplantable one.
#   CR5, CR6 — both are negative ("no closing reference appears"), and deleting a mechanism cannot
#         break "X must not happen" (ADR-0112 again). Inverting them means flipping the body's
#         `[ -n "$ISSUE" ]` guard, whose needle is not unique in the file: the same test guards the
#         argument validation thirty lines above. CR3 is their positive twin and IS planted, which
#         is what stops the pair going green against a body that never appends anything.

# --- CR8/CR9: the cross-file contract with project-conductor ---
CONDUCTOR="$SCRIPTS/../skills/project-conductor/SKILL.md"
# plant: CR8 | plugin/skills/project-conductor/SKILL.md | --issue "$_issue" | --base main
if [ -f "$CONDUCTOR" ]; then
  grep -q -- '--issue "\$_issue"' "$CONDUCTOR" \
    && ok "CR8 project-conductor passes --issue to publish-feature" \
    || no "CR8 project-conductor passes --issue to publish-feature"

  # The number is read BEFORE the checkbox flip, because the flip rewrites the roadmap line to end
  # in `(completed: <date>)` and can take the `(issue #N)` marker with it. Ordering, not presence:
  # both lines can exist and the feature still be broken.
# plant: CR9 | plugin/skills/project-conductor/SKILL.md | _issue=$(grep -F -- | _issue=$(true --
  _cap=$(grep -n '_issue=\$(grep -F' "$CONDUCTOR" | head -1 | cut -d: -f1)
  _flip=$(grep -n 'Update PROJECT.md: `- \[ \]' "$CONDUCTOR" | head -1 | cut -d: -f1)
  { [ -n "$_cap" ] && [ -n "$_flip" ] && [ "$_cap" -lt "$_flip" ]; } \
    && ok "CR9 the issue number is captured before the checkbox flip" \
    || no "CR9 the issue number is captured before the checkbox flip"
else
  no "CR8 project-conductor SKILL.md not found"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
