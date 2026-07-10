#!/bin/bash
# Phase 1 test harness (ADR-0022) — nightly-guard + publish-feature (offline, no network).
# Bash 3.2 clean. Run: bash phase1.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$SCRIPTS/nightly-guard.sh"
PUBLISH="$SCRIPTS/publish-feature.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

# assert_exit <expected> <label> -- reads actual exit from $? captured by caller
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkroot() { r="$tmp/$1"; mkdir -p "$r/.claude/nightly-state"; printf '%s' "$r"; }

# --- nightly-guard --check ---
R=$(mkroot clean)
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guard: clean root allows" || no "guard: clean root allows"

R=$(mkroot red); printf 'RED' > "$R/.claude/nightly-state/build-status"
out=$("$GUARD" --check "$R" 2>/dev/null); rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'NIGHTLY-GUARD HALT'; } \
  && ok "guard: RED build halts" || no "guard: RED build halts"

R=$(mkroot nh); printf 'missing logo asset' > "$R/.claude/needs-human"
out=$("$GUARD" --check "$R" 2>/dev/null); rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'missing logo asset'; } \
  && ok "guard: needs-human halts with reason" || no "guard: needs-human halts with reason"

R=$(mkroot rtf); printf 'BLOCKER: auth bypass' > "$R/.claude/nightly-state/rtf-blocker"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: rtf-blocker halts" || no "guard: rtf-blocker halts"

R=$(mkroot budg); printf 'limit=1000\nspent=1200\n' > "$R/.claude/nightly-state/token-budget"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: budget exceeded halts" || no "guard: budget exceeded halts"

R=$(mkroot budg2); printf 'limit=1000\nspent=500\n' > "$R/.claude/nightly-state/token-budget"
"$GUARD" --check "$R" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guard: budget under limit allows" || no "guard: budget under limit allows"

"$GUARD" --check "/no/such/dir/xyz" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guard: invalid root fail-safe blocks" || no "guard: invalid root fail-safe blocks"

# --- nightly-guard hook mode ---
if command -v jq >/dev/null 2>&1; then
  R=$(mkroot hookclean)
  echo "{\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: non-publish command inert" || no "guard hook: non-publish command inert"

  echo "{\"tool_input\":{\"command\":\"git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: publish without active marker inert" || no "guard hook: publish without active marker inert"

  touch "$R/.claude/nightly-state/active"
  printf 'RED' > "$R/.claude/nightly-state/build-status"
  echo "{\"tool_input\":{\"command\":\"gh pr create --base main\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "guard hook: active + RED blocks publish" || no "guard hook: active + RED blocks publish"

  rm -f "$R/.claude/nightly-state/build-status"
  echo "{\"tool_input\":{\"command\":\"git push -u origin feat/x\"},\"cwd\":\"$R\"}" | "$GUARD" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "guard hook: active + clean allows publish" || no "guard hook: active + clean allows publish"

  # Forbidden publishes during a nightly run must be blocked (review finding #1).
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

printf 'publish: true\n' > "$R/.claude/nightly-autopilot.yml"
out=$("$PUBLISH" --slug demo --root "$R" --dry-run 2>&1); rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'NIGHTLY-PUBLISH demo'; } \
  && ok "publish: opt-in + dry-run prints status line" || no "publish: opt-in + dry-run prints status line"

printf '%s' "$out" | grep -q -- '--force' && no "publish: dry-run must not use --force" || ok "publish: no --force in dry-run"

"$PUBLISH" --slug main --root "$R" --dry-run >/dev/null 2>&1
[ $? -eq 2 ] && ok "publish: slug=main refused" || no "publish: slug=main refused"

# guard integration: RED build blocks publish even with opt-in
printf 'RED' > "$R/.claude/nightly-state/build-status"
"$PUBLISH" --slug demo --root "$R" --dry-run >/dev/null 2>&1
[ $? -eq 2 ] && ok "publish: guard HALT aborts publish" || no "publish: guard HALT aborts publish"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
