#!/usr/bin/env bash
# selftest.sh — verification suite for the project-tasks skill.
#
# Builds a throwaway fixture repo under a mktemp directory, exercises scan.sh
# against it, and checks the skill's own structural contract. No network, no
# dependency beyond git and the shell.
#
#   bash scripts/selftest.sh        # exit 0 = all green

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$SKILL_DIR/scripts/scan.sh"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/project-tasks-selftest.XXXXXX")"
cleanup() {
  # Only ever removes the directory this run created.
  case "$FIXTURE" in
    */project-tasks-selftest.*) rm -rf "$FIXTURE" ;;
  esac
}
trap cleanup EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

# --- fixture -----------------------------------------------------------------
mkdir -p "$FIXTURE/repo/src" "$FIXTURE/repo/.claude" "$FIXTURE/empty"
cd "$FIXTURE/repo" || exit 1
git init -q .
git config user.email selftest@local
git config user.name selftest

cat > package.json <<'JSON'
{ "name": "fx", "main": "src/main.ts", "scripts": { "test": "vitest run" } }
JSON

cat > src/main.ts <<'TS'
// TODO: extract the bootstrap into its own module
export function main() {
  // FIXME: leaks a listener on retry
  return 1;
}
// Decoys: uppercase keyword embedded in a larger token. A regex without word
// boundaries matches these, which is exactly the failure this guards against.
const TODOS = [];
const DEBUGGING = true;
const HACKATHON = "not a marker";
TS

cat > src/legacy.js <<'JS'
// HACK: monkeypatch until upstream ships the fix
JS

echo "npm test" > .claude/test-cmd

cat > TODO.md <<'MD'
<!-- project-tasks: prefix=FX lastId=4 -->
# PROJECT TASKS

## Open Issues

- [ ] `FX-001` **P1** Listener leak on retry — `src/main.ts:3` <!-- src:marker opened:2026-08-01 -->
- [ ] `FX-002` **P2** Vendor monkeypatch — `src/legacy.js:1` <!-- src:marker opened:2026-08-01 -->
- [ ] `FX-003` **P2** Dead module still referenced — `src/gone.ts:10` <!-- src:marker opened:2026-08-01 -->
- [ ] `FX-004` **P3** Cleanup — `src/legacy.js:99` <!-- src:marker opened:2026-08-01 -->
MD

git add -A
git commit -qm "fix: fixture"

# --- scan.sh behaviour -------------------------------------------------------
printf '\nscan.sh\n'

OUT="$(bash "$SCAN" --root "$FIXTURE/repo" 2>/dev/null)"
check "exits 0 on a real project"        "0" "$?"
check "finds exactly 3 markers"          "3" "$(printf '%s\n' "$OUT" | grep -c '^MARKER')"
check "ignores embedded-keyword decoys"  "0" "$(printf '%s\n' "$OUT" | grep -c 'TODOS\|DEBUGGING\|HACKATHON')"
check "classifies FIXME"                 "1" "$(printf '%s\n' "$OUT" | grep -c '^MARKER.*FIXME')"
check "reports missing file as stale"    "1" "$(printf '%s\n' "$OUT" | grep -c '^STALE	FX-003.*file-missing')"
check "reports bad line as stale"        "1" "$(printf '%s\n' "$OUT" | grep -c '^STALE	FX-004.*line-out-of-range')"
check "no stale for live markers"        "0" "$(printf '%s\n' "$OUT" | grep -c '^STALE	FX-00[12]')"
check "detects entry point"              "1" "$(printf '%s\n' "$OUT" | grep -c '^MAP	entrypoint	src/main.ts')"
check "detects test-cmd"                 "1" "$(printf '%s\n' "$OUT" | grep -c '^MAP	test-cmd	npm test')"
check "picks up fix: commits"            "1" "$(printf '%s\n' "$OUT" | grep -c '^GITLOG')"

OUT2="$(bash "$SCAN" --root "$FIXTURE/repo" 2>/dev/null)"
if [ "$OUT" = "$OUT2" ]; then ok "two consecutive runs are identical"; else bad "two consecutive runs are identical"; fi

# A resolved marker must surface as a close candidate, never as a silent close.
printf 'export const legacy = 1;\n' > src/legacy.js
OUT3="$(bash "$SCAN" --root "$FIXTURE/repo" 2>/dev/null)"
check "removed marker becomes a candidate" "1" "$(printf '%s\n' "$OUT3" | grep -c '^STALE	FX-002.*marker-gone')"
check "ledger is never modified by scan"   "0" "$(git diff --quiet -- TODO.md; echo $?)"

bash "$SCAN" --root "$FIXTURE/empty" >/dev/null 2>&1
check "exits 3 outside a project"        "3" "$?"

MISSING="$(bash "$SCAN" --root "$FIXTURE/repo" --ledger "$FIXTURE/repo/NOPE.md" 2>/dev/null)"
check "handles an absent ledger"         "1" "$(printf '%s\n' "$MISSING" | grep -c '^MAP	ledger	absent')"

# grep fallback must agree with the ripgrep path
mkdir -p "$FIXTURE/nobin"
FB="$(PATH="$FIXTURE/nobin:/usr/bin:/bin" bash "$SCAN" --root "$FIXTURE/repo" 2>/dev/null)"
check "grep fallback finds the same markers" \
  "$(printf '%s\n' "$OUT3" | grep -c '^MARKER')" "$(printf '%s\n' "$FB" | grep -c '^MARKER')"

# --- skill structure ---------------------------------------------------------
printf '\nskill structure\n'

for f in SKILL.md reference/file-format.md reference/capture-sources.md \
         reference/chain-integration.md templates/TODO.template.md scripts/scan.sh; do
  if [ -f "$SKILL_DIR/$f" ]; then ok "present: $f"; else bad "present: $f"; fi
done

body_lines="$(wc -l < "$SKILL_DIR/SKILL.md" | tr -d ' ')"
if [ "$body_lines" -lt 500 ]; then ok "SKILL.md under 500 lines ($body_lines)"
else bad "SKILL.md under 500 lines" "$body_lines"; fi

if grep -rq '\\' "$SKILL_DIR/reference" "$SKILL_DIR/SKILL.md" 2>/dev/null; then
  bad "no Windows-style paths"
else ok "no Windows-style paths"; fi

# Every markdown link out of SKILL.md must resolve, and reference files must not
# chain to further local files (progressive disclosure stays one level deep).
broken=0
while IFS= read -r target; do
  [ -f "$SKILL_DIR/$target" ] || { broken=$((broken + 1)); printf '       unresolved: %s\n' "$target"; }
done <<EOF
$(grep -oE '\]\([a-zA-Z0-9_./-]+\.md\)' "$SKILL_DIR/SKILL.md" | tr -d '](' | tr -d ')')
EOF
check "SKILL.md links resolve" "0" "$broken"

nested="$(grep -ohE '\]\([a-zA-Z0-9_./-]+\.md\)' "$SKILL_DIR"/reference/*.md 2>/dev/null | wc -l | tr -d ' ')"
check "reference files do not nest links" "0" "$nested"

python3 - "$SKILL_DIR/SKILL.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
problems = []
if not m:
    problems.append("no YAML frontmatter")
else:
    fm = m.group(1)
    name = re.search(r"^name: (.+)$", fm, re.M)
    desc = re.search(r"^description: (.+)$", fm, re.M)
    if not name or not re.fullmatch(r"[a-z0-9-]{1,64}", name.group(1)):
        problems.append("name must be kebab-case, <=64 chars")
    elif any(w in name.group(1) for w in ("claude", "anthropic")):
        problems.append("name contains a reserved word")
    if not desc:
        problems.append("missing description")
    elif len(desc.group(1)) > 1024:
        problems.append(f"description is {len(desc.group(1))} chars, max 1024")
    elif re.search(r"<[a-zA-Z/]", fm):
        problems.append("frontmatter contains XML tags")
for p in problems:
    print(f"  FAIL frontmatter: {p}")
if not problems:
    print("  ok   frontmatter is valid")
sys.exit(1 if problems else 0)
PY
if [ $? -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi

# --- verdict -----------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
