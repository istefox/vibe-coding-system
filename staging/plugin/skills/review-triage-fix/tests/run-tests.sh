#!/bin/bash
# review-triage-fix helper unit harness. Isolated; never touches real state.
set -u
SK="$HOME/.claude/skills/review-triage-fix"
S="$SK/scripts"
TMP="$(mktemp -d)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- Task 1: verify.sh ---
# 1a: no .claude/test-cmd → UNVERIFIED
PA="$TMP/v_absent"; mkdir -p "$PA"
O=$(bash "$S/verify.sh" "$PA" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: absent test-cmd → UNVERIFIED" || bad "verify absent"
# 1b: NONE → UNVERIFIED (opt-out)
PN="$TMP/v_none/.claude"; mkdir -p "$PN"; printf 'NONE\n' > "$PN/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_none" 2>/dev/null)
[ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: NONE → UNVERIFIED" || bad "verify NONE"
# 1c: empty (comments only) → UNVERIFIED
PE="$TMP/v_empty/.claude"; mkdir -p "$PE"; printf '# only a comment\n\n' > "$PE/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_empty" 2>/dev/null)
[ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: empty → UNVERIFIED" || bad "verify empty"
# 1d: green → PASS
PG="$TMP/v_grn/.claude"; mkdir -p "$PG"; printf 'true\n' > "$PG/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_grn" 2>/dev/null)
[ "$O" = "PASS" ] && ok "verify: green → PASS" || bad "verify green"
# 1e: red → FAIL + tail captured
PR="$TMP/v_red/.claude"; mkdir -p "$PR"; printf 'echo BOOMTAIL >&2; exit 3\n' > "$PR/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_red" 2>/dev/null)
[ "${O%%$'\t'*}" = "FAIL" ] && echo "$O" | grep -q 'BOOMTAIL' && ok "verify: red → FAIL+tail" || bad "verify red"
# 1f: comment then real cmd → parsed (PASS)
PC="$TMP/v_cmt/.claude"; mkdir -p "$PC"; printf '# header\n\ntrue\n' > "$PC/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_cmt" 2>/dev/null)
[ "$O" = "PASS" ] && ok "verify: comment+cmd → parsed" || bad "verify comment-parse"
# 1g: timeout → UNVERIFIED (never blocks the cycle)
PT="$TMP/v_to/.claude"; mkdir -p "$PT"; printf 'sleep 5\n' > "$PT/test-cmd"
O=$(RTF_TEST_TIMEOUT=1 bash "$S/verify.sh" "$TMP/v_to" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: timeout → UNVERIFIED" || bad "verify timeout"

# --- Task 2: weakening-scan.sh ---
W="$S/weakening-scan.sh"
# 2a: clean non-test change → CLEAN
D=$(printf 'diff --git a/src/app.py b/src/app.py\n--- a/src/app.py\n+++ b/src/app.py\n@@ -1 +1 @@\n-x=1\n+x=2\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
[ "$O" = "CLEAN" ] && ok "weakening: clean src → CLEAN" || bad "weakening clean"
# 2b: assert removed in a test file → WEAKENED assert-removed
D=$(printf 'diff --git a/tests/test_x.py b/tests/test_x.py\n--- a/tests/test_x.py\n+++ b/tests/test_x.py\n@@ -1,3 +1,2 @@\n def test_a():\n-    assert foo() == 1\n+    foo()\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_x.py.*assert-removed' && ok "weakening: assert-removed" || bad "weakening assert"
# 2c: deleted test file → WEAKENED deleted-test-file
D=$(printf 'diff --git a/tests/test_y.py b/tests/test_y.py\ndeleted file mode 100644\n--- a/tests/test_y.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-def test_y():\n-    assert True\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_y.py.*deleted-test-file' && ok "weakening: deleted-file" || bad "weakening deleted"
# 2d: skip added → WEAKENED skip/xfail-added
D=$(printf 'diff --git a/spec/foo.spec.js b/spec/foo.spec.js\n--- a/spec/foo.spec.js\n+++ b/spec/foo.spec.js\n@@ -1,2 +1,2 @@\n-it("works", () => { expect(x).toBe(1) })\n+it.skip("works", () => { expect(x).toBe(1) })\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*foo.spec.js.*skip' && ok "weakening: skip-added" || bad "weakening skip"
# 2e: test fn removed, none added → WEAKENED test-removed-or-commented
D=$(printf 'diff --git a/tests/test_z.py b/tests/test_z.py\n--- a/tests/test_z.py\n+++ b/tests/test_z.py\n@@ -1,4 +1,1 @@\n-def test_z():\n-    assert g()\n+pass\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_z.py' && ok "weakening: test-removed" || bad "weakening test-removed"
# 2f: assert removed in NON-test file → ignored (CLEAN)
D=$(printf 'diff --git a/src/util.py b/src/util.py\n--- a/src/util.py\n+++ b/src/util.py\n@@ -1,2 +1,1 @@\n-    assert ok\n+    return\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
[ "$O" = "CLEAN" ] && ok "weakening: non-test assert ignored" || bad "weakening non-test"

# --- Task 3: triage-state.sh diff ---
T="$S/triage-state.sh"
SF="$TMP/.triage-fix-last.json"
# 3a: no prev state → all NEW, convergence stabile
rm -f "$SF"
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\nMINOR\tsrc/b.py:4\tnaming\n' | bash "$T" diff "$SF" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "$(echo "$O" | grep -c $'\tNEW$')" = "2" ] \
  && echo "$O" | grep -q $'^COUNTS\tresolved=0\topen=2\tnew=2\tregressed=0' \
  && ok "state diff: first run → 2 NEW" || bad "state diff first"
# seed a prev state via commit (tested fully in Task 4; used here as fixture)
printf 'MAJOR\tsrc/a.py:10\tmissing validation\topen\nMINOR\tsrc/b.py:4\tnaming\topen\n' | bash "$T" commit "$SF" 2>/dev/null
# 3b: one resolved (b gone), one still-open (a) → RESOLVED + STILL-OPEN, converge
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n' | bash "$T" diff "$SF" 2>/dev/null)
echo "$O" | grep -q $'src/a.py:10\tSTILL-OPEN' \
  && echo "$O" | grep -q $'\tRESOLVED' \
  && echo "$O" | grep -q $'^COUNTS\tresolved=1\topen=1\tnew=0\tregressed=0' \
  && echo "$O" | grep -q $'^CONVERGENCE\tconverge: 2→1 open' \
  && ok "state diff: resolved+still-open+converge" || bad "state diff resolved"
# 3c: previously-resolved finding reappears → REGRESSED
printf 'MAJOR\tsrc/a.py:10\tmissing validation\tresolved\n' | bash "$T" commit "$SF" 2>/dev/null
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n' | bash "$T" diff "$SF" 2>/dev/null)
echo "$O" | grep -q $'src/a.py:10\tREGRESSED' \
  && echo "$O" | grep -q $'^COUNTS\tresolved=0\topen=1\tnew=0\tregressed=1' \
  && ok "state diff: regressed" || bad "state diff regressed"
# 3d: stable ID — same finding hashes identically across calls (whitespace-normalized)
ID1=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n'   | bash "$T" diff "$TMP/none1.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
ID2=$(printf 'MAJOR\tsrc/a.py:10\t  missing   validation \n' | bash "$T" diff "$TMP/none2.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
[ -n "$ID1" ] && [ "$ID1" = "$ID2" ] && ok "state diff: stable normalized ID" || bad "state diff id"

# --- Task 4: triage-state.sh commit ---
T="$S/triage-state.sh"
# 4a: commit writes a JSON array with id/sev/loc/status
CF="$TMP/c_plain/.claude/.triage-fix-last.json"
printf 'BLOCKER\tsrc/x.py:9\tinjection\tresolved\nNIT\tsrc/y.py:1\tstyle\topen\n' | bash "$T" commit "$CF" 2>/dev/null
[ -f "$CF" ] && [ "$(jq 'length' "$CF" 2>/dev/null)" = "2" ] \
  && [ "$(jq -r '.[0]|.sev+"|"+.status' "$CF")" = "BLOCKER|resolved" ] \
  && ok "state commit: writes JSON array" || bad "state commit json"
# 4b: ID matches what diff computes for the same finding (round-trip stable)
ID_C=$(jq -r '.[1].id' "$CF")
ID_D=$(printf 'NIT\tsrc/y.py:1\tstyle\n' | bash "$T" diff "$TMP/none3.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
[ -n "$ID_C" ] && [ "$ID_C" = "$ID_D" ] && ok "state commit: id == diff id" || bad "state commit id"
# 4c: NON-git target → no .gitignore created, no error
NG="$TMP/c_nogit/.claude/.triage-fix-last.json"
printf 'MINOR\ta:1\tp\topen\n' | bash "$T" commit "$NG" 2>/dev/null; r=$?
[ $r -eq 0 ] && [ -f "$NG" ] && [ ! -e "$TMP/c_nogit/.gitignore" ] && ok "state commit: non-git → no gitignore" || bad "state commit nogit"
# 4d: git target → state-file path appended to repo .gitignore (idempotent)
GR="$TMP/c_git"; mkdir -p "$GR"; ( cd "$GR" && git init -q && git config user.email t@t && git config user.name t )
GF="$GR/.claude/.triage-fix-last.json"
printf 'MAJOR\tz:2\tq\topen\n' | bash "$T" commit "$GF" 2>/dev/null
printf 'MAJOR\tz:2\tq\topen\n' | bash "$T" commit "$GF" 2>/dev/null   # second call
[ "$(grep -c -F '.claude/.triage-fix-last.json' "$GR/.gitignore" 2>/dev/null)" = "1" ] \
  && ok "state commit: git → gitignored once" || bad "state commit gitignore"

# --- Task 5: SKILL.md structural completeness ---
M="$SK/SKILL.md"
g(){ grep -q -- "$1" "$M" 2>/dev/null && ok "SKILL.md: $2" || bad "SKILL.md missing: $2"; }
[ -f "$M" ] || bad "SKILL.md: file exists"
head -1 "$M" | grep -q '^---$' && grep -q '^name: review-triage-fix$' "$M" && ok "SKILL.md: frontmatter name" || bad "SKILL.md: frontmatter name"
grep -q '^description:.*invoc' "$M" && ok "SKILL.md: description" || bad "SKILL.md: description"
g 'scripts/verify.sh'        'invokes verify.sh'
g 'scripts/weakening-scan.sh' 'invokes weakening-scan.sh'
g 'scripts/triage-state.sh'  'invokes triage-state.sh'
g 'debugger'                 'routes to debugger'
g 'refactorer'               'routes to refactorer'
g 'coder'                    'routes to coder'
g 'micro-piano'              'coder micro-plan'
g 'REPORT-ONLY'              'report-only class'
g 'CIRCUIT BREAKER A'        'breaker A regressione'
g 'CIRCUIT BREAKER B'        'breaker B anti-weakening'
g 'CIRCUIT BREAKER C'        'breaker C security'
g 'CIRCUIT BREAKER D'        'breaker D unverified'
g 'NO COMMIT'                'no-commit invariant'
g 'STOP'                     'single-cycle STOP'
g 'sub-agent'                'sub-agent-no-spawn constraint'
g 'sequential'               'sequential dispatch'
g '.triage-fix-last-'        'cross-cycle per-branch state file'
g 'RTF_SF'                   'per-branch state-file variable'
g '_no-git'                  'non-git fallback branch name'
g 'Add+Remove rule'          'add+remove substitution rule'

# --- Task 6: coder.md classifier section ---
C="$HOME/.claude/agents/coder.md"
grep -q -- 'Pre-flight Pattern Classifier' "$C" 2>/dev/null && ok "coder.md: classifier section present" || bad "coder.md: classifier section missing"
grep -q -- 'PATTERN: <CATEGORY>' "$C" 2>/dev/null && ok "coder.md: PATTERN format spec present" || bad "coder.md: PATTERN format spec missing"

# --- Task 7: refactorer.md snapshot harness section ---
R="$HOME/.claude/agents/refactorer.md"
grep -q -- 'Snapshot Harness Integration' "$R" 2>/dev/null && ok "refactorer.md: snapshot integration section present" || bad "refactorer.md: snapshot integration section missing"
grep -q -- 'refactor-snapshot' "$R" 2>/dev/null && ok "refactorer.md: refactor-snapshot skill reference present" || bad "refactorer.md: refactor-snapshot skill reference missing"

# --- Task 8: concept-to-code skill section ---
S="$HOME/.claude/skills/concept-to-code/SKILL.md"
[ -f "$S" ] && ok "concept-to-code: SKILL.md present" || bad "concept-to-code: SKILL.md missing"
grep -q -- 'manifest_schema_version' "$S" 2>/dev/null && ok "concept-to-code: manifest_schema_version reference present" || bad "concept-to-code: manifest_schema_version reference missing"


# --- Task 7: pre-flight-pattern-enforce hook ---
S="$HOME/.claude/settings.json"
grep -q -- 'pre-flight-pattern-enforce' "$S" 2>/dev/null && ok "settings.json: pre-flight-pattern-enforce hook registered" || bad "settings.json: pre-flight-pattern-enforce hook missing"

# --- Task 9: vibe-status skill ---
V="$HOME/.claude/skills/vibe-status/SKILL.md"
grep -q -- 'Vibe-Coding System Status' "$V" 2>/dev/null && ok "vibe-status: SKILL.md present" || bad "vibe-status: SKILL.md missing"

# --- design-brainstorm skill section ---
DB="$HOME/.claude/skills/design-brainstorm/SKILL.md"
[ -f "$DB" ] && ok "design-brainstorm: SKILL.md present" || bad "design-brainstorm: SKILL.md missing"
grep -q -- 'BRAINSTORM.md' "$DB" 2>/dev/null && ok "design-brainstorm: BRAINSTORM.md output contract present" || bad "design-brainstorm: BRAINSTORM.md contract missing"

# --- db-backup-guardrail hook ---
S="$HOME/.claude/settings.json"
grep -q -- 'db-backup-guardrail' "$S" 2>/dev/null && ok "settings.json: db-backup-guardrail hook registered" || bad "settings.json: db-backup-guardrail hook missing"

# --- Task 10: per-branch state-file naming logic ---
# Helper: replicate the RTF_SF shell snippet from SKILL.md Step 0.
# Input: root, branch_raw → output: sanitized filename (basename only).
rtf_sf_name() {
  local _branch="$1"
  case "$_branch" in
    "") _branch="_no-git" ;;
    HEAD) _branch="_detached" ;;
  esac
  _branch=$(printf '%s' "$_branch" | sed 's/[^a-zA-Z0-9._-]/_/g')
  printf '.triage-fix-last-%s.json\n' "$_branch"
}

# 10a: normal branch → filename uses branch name
N=$(rtf_sf_name "main")
[ "$N" = ".triage-fix-last-main.json" ] && ok "per-branch: main → correct filename" || bad "per-branch: main filename"

# 10b: branch with slash (feature/foo) → slash sanitized to underscore
N=$(rtf_sf_name "feature/add-login")
[ "$N" = ".triage-fix-last-feature_add-login.json" ] && ok "per-branch: feature/add-login → sanitized" || bad "per-branch: slash sanitized"

# 10c: no git / empty branch → _no-git fallback
N=$(rtf_sf_name "")
[ "$N" = ".triage-fix-last-_no-git.json" ] && ok "per-branch: empty → _no-git fallback" || bad "per-branch: no-git fallback"

# 10d: detached HEAD → _detached fallback
N=$(rtf_sf_name "HEAD")
[ "$N" = ".triage-fix-last-_detached.json" ] && ok "per-branch: HEAD → _detached fallback" || bad "per-branch: detached fallback"

# 10e: two branches produce distinct filenames → no cross-contamination
N1=$(rtf_sf_name "main"); N2=$(rtf_sf_name "fix/bug-42")
[ "$N1" != "$N2" ] && ok "per-branch: main != fix/bug-42 (distinct files)" || bad "per-branch: branches not distinct"

# 10f: commit in non-git dir produces per-branch file, not the old generic one
NG2="$TMP/pb_nogit/.claude"
mkdir -p "$NG2"
branch_fallback=$(git -C "$TMP/pb_nogit" rev-parse --abbrev-ref HEAD 2>/dev/null); r=$?
# r!=0 or empty → _no-git
case "$branch_fallback" in "") branch_fallback="_no-git";; HEAD) branch_fallback="_detached";; esac
branch_san=$(printf '%s' "$branch_fallback" | sed 's/[^a-zA-Z0-9._-]/_/g')
expected_sf="$NG2/.triage-fix-last-${branch_san}.json"
printf 'MINOR\ta:1\tp\topen\n' | bash "$T" commit "$expected_sf" 2>/dev/null; r=$?
[ $r -eq 0 ] && [ -f "$expected_sf" ] \
  && ok "per-branch: non-git commit writes per-branch file" \
  || bad "per-branch: non-git commit file"


# --- clean-public-repo skill (ADR-0011) ---
CPR="$HOME/.claude/skills/clean-public-repo/SKILL.md"
[ -f "$CPR" ] && ok "clean-public-repo: SKILL.md present" || bad "clean-public-repo: SKILL.md missing"
grep -q -- 'orchestrator' "$CPR" 2>/dev/null && ok "clean-public-repo: orchestrator-only documented" || bad "clean-public-repo: orchestrator-only missing"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
