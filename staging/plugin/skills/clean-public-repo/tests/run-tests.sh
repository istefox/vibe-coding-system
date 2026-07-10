#!/bin/bash
# clean-public-repo self-test harness
# Target: PASS=18 FAIL=0
# Tests: 11 structural anchors on SKILL.md + 3 smoke detect-public-remote + 4 smoke detect-tool-traces
# Bash 3.2-clean: no assoc arrays, no mapfile, no ${v^^}, no <(), no <<<
set -u

S="$HOME/.claude/skills/clean-public-repo/SKILL.md"
DR="$HOME/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh"
DT="$HOME/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh"
TMP=$(mktemp -d)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# Helper: run detect-public-remote on a dir, return first line of output
pr() {
  bash "$DR" "$1" 2>/dev/null | head -1
}

# -----------------------------------------------------------------------
# A. Structural anchors on SKILL.md (11 tests)
# -----------------------------------------------------------------------

# 1: SKILL.md file exists
[ -f "$S" ] && ok "SKILL.md: file present" || bad "SKILL.md: file missing"

# 2: frontmatter name: clean-public-repo
grep -q 'name: clean-public-repo' "$S" 2>/dev/null \
  && ok "SKILL.md: name: clean-public-repo present" \
  || bad "SKILL.md: name: clean-public-repo missing"

# 3: negative anchor — disable-model-invocation: true must NOT be present
! grep -q 'disable-model-invocation: true' "$S" 2>/dev/null \
  && ok "SKILL.md: no disable-model-invocation (correct)" \
  || bad "SKILL.md: disable-model-invocation found (must be absent)"

# 4: orchestrator-only constraint documented
grep -q 'orchestrator' "$S" 2>/dev/null \
  && ok "SKILL.md: orchestrator-only documented" \
  || bad "SKILL.md: orchestrator-only missing"

# 5: ethics statement — mai falsifica / never falsify (hard ethical constraint)
grep -Eqi 'mai falsifica|no falsificazione|never falsif' "$S" 2>/dev/null \
  && ok "SKILL.md: ethics anchor (no falsification) present" \
  || bad "SKILL.md: ethics anchor missing"

# 6: COVERAGE & LIMITS section (mandatory report coverage+limits)
grep -Eqi 'COVERAGE & LIMITS' "$S" 2>/dev/null \
  && ok "SKILL.md: COVERAGE & LIMITS section present" \
  || bad "SKILL.md: COVERAGE & LIMITS section missing"

# 7: fresh-history (default strategy for already-public repos)
grep -Eqi 'fresh-history' "$S" 2>/dev/null \
  && ok "SKILL.md: fresh-history strategy present" \
  || bad "SKILL.md: fresh-history missing"

# 8: rewrite chirurgico / surgical (option 2)
grep -Eqi 'rewrite chirurgico|surgical' "$S" 2>/dev/null \
  && ok "SKILL.md: surgical rewrite (option 2) present" \
  || bad "SKILL.md: surgical rewrite missing"

# 9: dry-run (safety before apply)
grep -Eqi 'dry-run' "$S" 2>/dev/null \
  && ok "SKILL.md: dry-run safety present" \
  || bad "SKILL.md: dry-run missing"

# 10: force-push with HITL/confirmation nearby (destructive safety)
grep -Eqi 'force-push' "$S" 2>/dev/null \
  && grep -B5 -A5 'force-push' "$S" 2>/dev/null | grep -Eqi 'HITL|confirmation' \
  && ok "SKILL.md: force-push + HITL/confirmation documented" \
  || bad "SKILL.md: force-push HITL/confirmation missing"

# 11: ## When to invoke section (structural anchor replacing former ## Lingua check)
grep -q '## When to invoke' "$S" 2>/dev/null \
  && ok "SKILL.md: ## When to invoke section present" \
  || bad "SKILL.md: ## When to invoke section missing"

# -----------------------------------------------------------------------
# B. Smoke: detect-public-remote.sh (3 tests — anti falso-avvio)
# -----------------------------------------------------------------------

# 12: non-git dir → silent
DIR12="$TMP/t12_nongit"
mkdir -p "$DIR12"
OUT12=$(pr "$DIR12")
[ "$OUT12" = "silent" ] \
  && ok "detect-public-remote: non-git dir → silent" \
  || bad "detect-public-remote: non-git dir should be silent, got: $OUT12"

# 13: git init without any remote → silent
DIR13="$TMP/t13_noremote"
mkdir -p "$DIR13"
( cd "$DIR13" && git init -q ) 2>/dev/null
OUT13=$(pr "$DIR13")
[ "$OUT13" = "silent" ] \
  && ok "detect-public-remote: git without remote → silent" \
  || bad "detect-public-remote: no-remote should be silent, got: $OUT13"

# 14: git init + gitlab.com remote → silent (host not github)
DIR14="$TMP/t14_gitlab"
mkdir -p "$DIR14"
( cd "$DIR14" && git init -q && git remote add origin git@gitlab.com:someuser/somerepo.git ) 2>/dev/null
OUT14=$(pr "$DIR14")
[ "$OUT14" = "silent" ] \
  && ok "detect-public-remote: gitlab remote → silent (not github)" \
  || bad "detect-public-remote: gitlab should be silent, got: $OUT14"

# -----------------------------------------------------------------------
# C. Smoke: detect-tool-traces.sh (4 tests)
# -----------------------------------------------------------------------

# 15: file with "# added by Claude" → output contains auto-removable
DIR15="$TMP/t15_trace"
mkdir -p "$DIR15"
printf 'def f():\n    return 1  # added by Claude\n' > "$DIR15/a.py"
OUT15=$(bash "$DT" "$DIR15" 2>/dev/null)
echo "$OUT15" | grep -q 'auto-removable' \
  && ok "detect-tool-traces: comment-trace → auto-removable found" \
  || bad "detect-tool-traces: comment-trace should produce auto-removable"

# 16: package.json with claude-sdk dependency → review-needed (NOT auto-removable for that match)
DIR16="$TMP/t16_dep"
mkdir -p "$DIR16"
printf '{"dependencies":{"claude-sdk":"^1.0.0"}}\n' > "$DIR16/package.json"
OUT16=$(bash "$DT" "$DIR16" 2>/dev/null)
# Single conceptual test (plan T7 #16): claude-sdk dep marked review-needed AND that
# package.json match is NOT auto-removable (false-positive regression guard, both asserted together).
PKG_LINE=$(echo "$OUT16" | grep 'package.json' | head -1)
if echo "$OUT16" | grep -q 'review-needed' && ! echo "$PKG_LINE" | grep -q 'auto-removable'; then
  ok "detect-tool-traces: claude-sdk dep → review-needed, not auto-removable (regression guard)"
else
  bad "detect-tool-traces: claude-sdk dep must be review-needed and NOT auto-removable (regression)"
fi

# 17: clean file (no markers) → exit 0, no auto-removable in output
DIR17="$TMP/t17_clean"
mkdir -p "$DIR17"
printf 'def hello():\n    return "world"\n' > "$DIR17/clean.py"
bash "$DT" "$DIR17" 2>/dev/null
EC17=$?
[ $EC17 -eq 0 ] \
  && ok "detect-tool-traces: clean file → exit 0 (no auto-removable)" \
  || bad "detect-tool-traces: clean file should exit 0, got exit $EC17"

# 18: decorative emoji + word "claude" in .md → auto-removable string-emoji
DIR18="$TMP/t18_emoji"
mkdir -p "$DIR18"
printf '# My Project\n\nBuilt with love by claude :sparkles:\n' > "$DIR18/README.md"
OUT18=$(bash "$DT" "$DIR18" 2>/dev/null)
echo "$OUT18" | grep -q 'auto-removable' \
  && ok "detect-tool-traces: emoji+claude in .md → auto-removable" \
  || bad "detect-tool-traces: emoji+claude .md should be auto-removable"

# 19: typographic Unicode (≤) + "claude", no branding/emoji → review-needed (NOT auto-removable).
# Regression from pilot Devonthink_MCP: em-dash/arrow/§/≤/box-drawing/accents must NOT count as emoji.
DIR19="$TMP/t19_typo"
mkdir -p "$DIR19"
printf 'Tool description \xe2\x89\xa4 2KB (limite Claude Code)\n' > "$DIR19/doc.md"
OUT19=$(bash "$DT" "$DIR19" 2>/dev/null)
TYPO_LINE=$(echo "$OUT19" | grep 'doc.md' | head -1)
if echo "$TYPO_LINE" | grep -q 'review-needed' && ! echo "$TYPO_LINE" | grep -q 'auto-removable'; then
  ok "detect-tool-traces: typographic Unicode + claude → review-needed (not auto-removable)"
else
  bad "detect-tool-traces: typographic+claude should be review-needed, got: $TYPO_LINE"
fi

# 20: real 4-byte emoji (🚀 U+1F680) + "claude", no branding word → auto-removable (emoji path still works).
DIR20="$TMP/t20_realemoji"
mkdir -p "$DIR20"
printf 'release \xf0\x9f\x9a\x80 by claude\n' > "$DIR20/notes.md"
OUT20=$(bash "$DT" "$DIR20" 2>/dev/null)
echo "$OUT20" | grep 'notes.md' | grep -q 'auto-removable' \
  && ok "detect-tool-traces: real 4-byte emoji + claude → auto-removable" \
  || bad "detect-tool-traces: real emoji+claude should be auto-removable"

# 21: trailer shown in docs (inside backticks / after negation) → review-needed, NOT auto-removable.
# Regression from pilot Devonthink_MCP: plan docs describing the "no Co-Authored-By" convention.
DIR21="$TMP/t21_docmention"
mkdir -p "$DIR21"
printf -- '- No `Co-Authored-By: Claude` trailer in any commit (per project convention).\n' > "$DIR21/plan.md"
OUT21=$(bash "$DT" "$DIR21" 2>/dev/null)
TRL_LINE=$(echo "$OUT21" | grep 'plan.md' | grep -i 'Co-Authored' | head -1)
if echo "$TRL_LINE" | grep -q 'review-needed' && ! echo "$TRL_LINE" | grep -q 'auto-removable'; then
  ok "detect-tool-traces: trailer in docs (backtick/negation) → review-needed"
else
  bad "detect-tool-traces: doc-mention trailer should be review-needed, got: $TRL_LINE"
fi

# 22: real trailer (no backtick, no negation) → auto-removable (still detected).
DIR22="$TMP/t22_realtrailer"
mkdir -p "$DIR22"
printf 'Co-Authored-By: Claude <noreply@anthropic.com>\n' > "$DIR22/msg.txt"
OUT22=$(bash "$DT" "$DIR22" 2>/dev/null)
echo "$OUT22" | grep -i 'Co-Authored' | grep -q 'auto-removable' \
  && ok "detect-tool-traces: real trailer (no backtick/negation) → auto-removable" \
  || bad "detect-tool-traces: real trailer should stay auto-removable"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
rm -rf "$TMP"
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
