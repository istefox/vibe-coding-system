#!/bin/bash
# codex-coder-dispatch-gate.test.sh — ADR-0196.
#
# Covers SPEC R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09, R-10, R-12.
# This is an offline, hermetic RED harness: it never calls a live Codex service and it owns only
# scratch repositories under mktemp -d. Production implementation belongs to later plan tasks.
# Bash 3.2 clean. Run: bash codex-coder-dispatch-gate.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
CC="$SCRIPTS/codex-coder.sh"
CR="$SCRIPTS/codex-reviewer.sh"
CT="$SCRIPTS/codex-tester.sh"
SYNC="$SCRIPTS/../../sync-to-claude.sh"
STEP5="$SCRIPTS/../skills/concept-to-code/references/step5-implementation.md"
MINIT="$SCRIPTS/../skills/concept-to-code/scripts/manifest-init.sh"
MVALIDATE="$SCRIPTS/../skills/concept-to-code/scripts/manifest-validate.sh"
MSETFLAG="$SCRIPTS/../skills/concept-to-code/scripts/manifest-set-flag.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# FATAL only for inputs that pre-date this feature. codex-coder.sh is deliberately excluded:
# CK01 must report its absence without preventing the remaining assertion ids from running.
for _f in "$CR" "$CT" "$SYNC" "$STEP5" "$MINIT" "$MVALIDATE" "$MSETFLAG"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

real_bash=$(command -v bash)
SCRATCH_ROOT=$(mktemp -d)
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

# make_stub_codex <dir> <auth-status> <exec-behaviour-script>
# Writes an executable `codex` into <dir> that answers `doctor --json` with the given
# auth.credentials status and, on `exec`, runs <exec-behaviour-script> with the parsed
# -C/-o values in $CC_CD/$CC_OUT and records its own argv to <dir>/argv.txt.
make_stub_codex() {
  _msc_dir="$1"; _msc_auth="$2"; _msc_behav="$3"
  cat > "$_msc_dir/codex" <<STUB_EOF
#!/bin/bash
set -u
case "\${1:-}" in
  doctor)
    echo '{"checks":{"auth.credentials":{"status":"$_msc_auth"}}}'
    exit 0
    ;;
  exec)
    shift
    : > "$_msc_dir/argv.txt"
    for _a in "\$@"; do printf '%s\n' "\$_a" >> "$_msc_dir/argv.txt"; done
    CC_CD=""
    CC_OUT=""
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        -C) CC_CD="\$2"; shift 2 ;;
        -o) CC_OUT="\$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    export CC_CD CC_OUT
    if [ -n "\$CC_OUT" ]; then
      cat > "\$CC_OUT" <<'RESULT_EOF'
{"files_modified":[],"sub_steps":{"executed":[],"left_out":[]},"key_decisions":[],"verification":{"command":"true","exit_code":0,"result":"passed"},"drafted_commit":{"subject":"test: probe","body":""},"cleanup":[],"plan_deviations":[],"pattern_classification":[]}
RESULT_EOF
    fi
    bash "$_msc_behav"
    exit "\$?"
    ;;
  *)
    echo "stub-codex: unrecognised command '\${1:-}'" >&2
    exit 1
    ;;
esac
STUB_EOF
  chmod +x "$_msc_dir/codex"
}

mk_behav() { cat > "$1"; }

new_repo_empty() {
  mkdir -p "$1"
  ( cd "$1" \
      && git init -q >/dev/null 2>&1 \
      && git config user.email t@example.com \
      && git config user.name test \
      && printf '# scratch\n' > README.md \
      && git add README.md \
      && git commit -qm init >/dev/null 2>&1 )
}

new_repo_with_prod() {
  mkdir -p "$1"
  ( cd "$1" \
      && git init -q >/dev/null 2>&1 \
      && git config user.email t@example.com \
      && git config user.name test \
      && mkdir -p src \
      && printf 'print("orig")\n' > src/prod.py \
      && git add src/prod.py \
      && git commit -qm init >/dev/null 2>&1 )
}

flat_count_text() {
  python3 -c '
import re, sys
def flat(s):
    s = re.sub(r"[`*_]", "", s)
    return re.sub(r"\s+", " ", s).lower()
print(flat(sys.argv[1]).count(flat(sys.argv[2])))
' "$1" "$2"
}

flat_regex_text() {
  python3 -c '
import re, sys
text = re.sub(r"[`*_]", "", sys.argv[1])
text = re.sub(r"\s+", " ", text).lower()
print(1 if re.search(sys.argv[2], text) else 0)
' "$1" "$2"
}

slice_heading() {
  awk -v h="$1" '
    $0 == h { grab=1; print; next }
    grab && /^#### / { exit }
    grab { print }
  ' "$2"
}

# =====================================================================================
# Script existence, deployment, sandbox, and invocation.
if [ -f "$CC" ] && [ -r "$CC" ]; then
  ok "CK01 (R-04): staging/plugin/scripts/codex-coder.sh exists and is readable"
else
  bad "CK01 (R-04): staging/plugin/scripts/codex-coder.sh does not exist or is not readable"
fi

CK02_COUNT=$(grep -cF 'plugin/scripts/codex-coder.sh|hooks/codex-coder.sh' "$SYNC")
if [ "$CK02_COUNT" -eq 1 ]; then
  ok "CK02: sync-to-claude.sh deploys codex-coder.sh through PAIRS exactly once"
else
  bad "CK02: expected exactly 1 codex-coder.sh PAIRS line, found $CK02_COUNT"
fi
# plant: CK02 | sync-to-claude.sh | plugin/scripts/codex-coder.sh|hooks/codex-coder.sh | plugin/scripts/codex-coder.sh|hooks/codex-coder-REMOVED.sh

CK03_INVOKE=$(awk '
  /^codex exec/ { grab=1 }
  grab { print; if ($0 !~ /\\$/) { exit } }
' "$CC" 2>/dev/null)
if printf '%s' "$CK03_INVOKE" | grep -qF -- '-s workspace-write' \
   && printf '%s' "$CK03_INVOKE" | grep -qF -- '-C "$WORKTREE"'; then
  ok 'CK03 (R-05): the codex exec slice carries -s workspace-write and -C "$WORKTREE"'
else
  bad "CK03 (R-05): the codex exec slice is absent or missing its workspace/write flags"
fi
# plant: CK03 | plugin/scripts/codex-coder.sh | -s workspace-write | -s read-only

if [ -z "$CK03_INVOKE" ]; then
  bad "CK04 (R-05): no codex exec invocation slice exists to inspect"
elif printf '%s' "$CK03_INVOKE" | grep -qF -- 'danger-full-access' \
     || printf '%s' "$CK03_INVOKE" | grep -qF -- 'read-only'; then
  bad "CK04 (R-05): the codex exec invocation uses a forbidden sandbox"
else
  ok "CK04 (R-05): the codex exec slice contains neither danger-full-access nor read-only"
fi

# =====================================================================================
# Availability cascade and required invocation contract.
CK05_PATH="$SCRATCH_ROOT/ck05_path"; mkdir -p "$CK05_PATH"
CK05_RESOLVED=$(PATH="$CK05_PATH:/usr/bin:/bin" "$real_bash" -c 'command -v codex' 2>/dev/null || true)
if [ -n "$CK05_RESOLVED" ]; then
  bad "CK05 (R-04): DID-NOT-RUN precondition failed because codex resolved at $CK05_RESOLVED"
else
  CK05_WT="$SCRATCH_ROOT/ck05_wt"; mkdir -p "$CK05_WT"
  CK05_BRIEF="$SCRATCH_ROOT/ck05_brief"; printf 'brief\n' > "$CK05_BRIEF"
  CK05_ERR="$SCRATCH_ROOT/ck05_err"
  PATH="$CK05_PATH:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK05_WT" \
    --brief "$CK05_BRIEF" --out "$SCRATCH_ROOT/ck05_out" --model astra --effort medium \
    >/dev/null 2>"$CK05_ERR"
  CK05_RC=$?
  if [ "$CK05_RC" -eq 3 ] && grep -qE '^codex-coder: DID-NOT-RUN:' "$CK05_ERR"; then
    ok "CK05 (R-04): no codex on PATH exits 3 with the DID-NOT-RUN prefix"
  else
    bad "CK05 (R-04): no-codex case returned $CK05_RC: $(cat "$CK05_ERR" 2>/dev/null)"
  fi
fi

CK06_STUB="$SCRATCH_ROOT/ck06_stub"; mkdir -p "$CK06_STUB"
CK06_BEHAV="$SCRATCH_ROOT/ck06_behav"; printf 'exit 0\n' > "$CK06_BEHAV"
make_stub_codex "$CK06_STUB" error "$CK06_BEHAV"
CK06_WT="$SCRATCH_ROOT/ck06_wt"; mkdir -p "$CK06_WT"
CK06_BRIEF="$SCRATCH_ROOT/ck06_brief"; printf 'brief\n' > "$CK06_BRIEF"
CK06_ERR="$SCRATCH_ROOT/ck06_err"
PATH="$CK06_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK06_WT" \
  --brief "$CK06_BRIEF" --out "$SCRATCH_ROOT/ck06_out" --model astra --effort medium \
  >/dev/null 2>"$CK06_ERR"
CK06_RC=$?
if [ "$CK06_RC" -eq 3 ] && grep -qF 'error' "$CK06_ERR"; then
  ok "CK06 (R-04): auth.credentials.status=error exits 3 and names the status"
else
  bad "CK06 (R-04): auth error returned $CK06_RC: $(cat "$CK06_ERR" 2>/dev/null)"
fi

CK07_STUB="$SCRATCH_ROOT/ck07_stub"; mkdir -p "$CK07_STUB"
CK07_BEHAV="$SCRATCH_ROOT/ck07_behav"; printf 'exit 0\n' > "$CK07_BEHAV"
make_stub_codex "$CK07_STUB" ok "$CK07_BEHAV"
CK07_WT="$SCRATCH_ROOT/ck07_wt"; mkdir -p "$CK07_WT"
CK07_BRIEF="$SCRATCH_ROOT/ck07_brief"; printf 'brief\n' > "$CK07_BRIEF"
CK07_BAD_BRIEF="$SCRATCH_ROOT/ck07_not_a_file"; mkdir -p "$CK07_BAD_BRIEF"
CK07_OUT="$SCRATCH_ROOT/ck07_out"
ck07_case() {
  PATH="$CK07_STUB:/usr/bin:/bin" "$real_bash" "$CC" "$@" >/dev/null 2>/dev/null
  [ "$?" -eq 2 ]
}
CK07_FAILS=""
ck07_case --bogus --worktree "$CK07_WT" --brief "$CK07_BRIEF" --out "$CK07_OUT" --model astra --effort medium || CK07_FAILS="$CK07_FAILS unknown-flag"
ck07_case --brief "$CK07_BRIEF" --out "$CK07_OUT" --model astra --effort medium || CK07_FAILS="$CK07_FAILS missing-worktree"
ck07_case --worktree "$CK07_WT" --brief "$CK07_BRIEF" --model astra --effort medium || CK07_FAILS="$CK07_FAILS missing-out"
ck07_case --worktree "$CK07_WT" --brief "$CK07_BAD_BRIEF" --out "$CK07_OUT" --model astra --effort medium || CK07_FAILS="$CK07_FAILS unreadable-brief"
ck07_case --worktree "$CK07_WT" --brief "$CK07_BRIEF" --out "$CK07_OUT" --effort medium || CK07_FAILS="$CK07_FAILS missing-model"
ck07_case --worktree "$CK07_WT" --brief "$CK07_BRIEF" --out "$CK07_OUT" --model astra || CK07_FAILS="$CK07_FAILS missing-effort"
ck07_case --worktree "$CK07_WT" --brief "$CK07_BRIEF" --out "$CK07_OUT" --model terra --effort medium || CK07_FAILS="$CK07_FAILS terra-model"
if [ -z "$CK07_FAILS" ]; then
  ok "CK07 (R-04): all 7 bad-invocation cases exit 2"
else
  bad "CK07 (R-04): bad-invocation cases did not exit 2:$CK07_FAILS"
fi

CK08_REPO="$SCRATCH_ROOT/ck08_repo"; new_repo_empty "$CK08_REPO"
CK08_STUB="$SCRATCH_ROOT/ck08_stub"; mkdir -p "$CK08_STUB"
CK08_BEHAV="$SCRATCH_ROOT/ck08_behav"; printf 'exit 0\n' > "$CK08_BEHAV"
make_stub_codex "$CK08_STUB" ok "$CK08_BEHAV"
CK08_BRIEF="$SCRATCH_ROOT/ck08_brief"; printf 'brief\n' > "$CK08_BRIEF"
PATH="$CK08_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK08_REPO" \
  --brief "$CK08_BRIEF" --out "$SCRATCH_ROOT/ck08_out" --model astra --effort high \
  >/dev/null 2>/dev/null
CK08_RC=$?
if [ "$CK08_RC" -eq 0 ] && grep -qFx -- '-c model=gpt-6-astra' "$CK08_STUB/argv.txt" 2>/dev/null \
   && grep -qFx -- '-c model_reasoning_effort=high' "$CK08_STUB/argv.txt" 2>/dev/null; then
  ok "CK08 (R-04): astra/high maps to the explicit model and reasoning-effort argv"
else
  bad "CK08 (R-04): astra/high argv mapping is absent or the run returned $CK08_RC"
fi
# plant: CK08 | plugin/scripts/codex-coder.sh | gpt-6-astra | gpt-6-astro

CK09_REPO="$SCRATCH_ROOT/ck09_repo"; new_repo_empty "$CK09_REPO"
CK09_STUB="$SCRATCH_ROOT/ck09_stub"; mkdir -p "$CK09_STUB"
CK09_BEHAV="$SCRATCH_ROOT/ck09_behav"; printf 'exit 0\n' > "$CK09_BEHAV"
make_stub_codex "$CK09_STUB" ok "$CK09_BEHAV"
CK09_BRIEF="$SCRATCH_ROOT/ck09_brief"; printf 'brief\n' > "$CK09_BRIEF"
PATH="$CK09_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK09_REPO" \
  --brief "$CK09_BRIEF" --out "$SCRATCH_ROOT/ck09_out" --model sol --effort low \
  >/dev/null 2>/dev/null
CK09_RC=$?
if [ "$CK09_RC" -eq 0 ] && grep -qFx -- '-c model=gpt-5.6-sol' "$CK09_STUB/argv.txt" 2>/dev/null; then
  ok "CK09 (R-04): sol maps to -c model=gpt-5.6-sol"
else
  bad "CK09 (R-04): sol argv mapping is absent or the run returned $CK09_RC"
fi

CK10_REGEX="'usage limit|rate limit|quota exceeded|\\b429\\b'"
CK10_PRECEDENCE='[ -s "$RAW_OUT" ]'
CK10_MISSING=""
for _f in "$CR" "$CT" "$CC"; do
  grep -qF -- "$CK10_REGEX" "$_f" 2>/dev/null || CK10_MISSING="$CK10_MISSING regex:$(basename "$_f")"
  grep -qF -- "$CK10_PRECEDENCE" "$_f" 2>/dev/null || CK10_MISSING="$CK10_MISSING precedence:$(basename "$_f")"
done
if [ -z "$CK10_MISSING" ]; then
  ok "CK10 (R-04): all three Codex scripts share the exact rate-limit regex and output precedence"
else
  bad "CK10 (R-04): three-script availability drift:$CK10_MISSING"
fi

# =====================================================================================
# Scope check. Each fixture asserts exit polarity and the named violation class.
CK11_REPO="$SCRATCH_ROOT/ck11_repo"; new_repo_empty "$CK11_REPO"
CK11_STUB="$SCRATCH_ROOT/ck11_stub"; mkdir -p "$CK11_STUB"
CK11_BEHAV="$SCRATCH_ROOT/ck11_behav"
mk_behav "$CK11_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CC_CD/.claude"
printf 'bash tests\n' > "$CC_CD/.claude/test-cmd"
exit 0
BEHAV_EOF
make_stub_codex "$CK11_STUB" ok "$CK11_BEHAV"
CK11_BRIEF="$SCRATCH_ROOT/ck11_brief"; printf 'brief\n' > "$CK11_BRIEF"
CK11_ERR="$SCRATCH_ROOT/ck11_err"
PATH="$CK11_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK11_REPO" --brief "$CK11_BRIEF" --out "$SCRATCH_ROOT/ck11_out" --model astra --effort medium >/dev/null 2>"$CK11_ERR"
CK11_RC=$?
if [ "$CK11_RC" -eq 4 ] && grep -qF 'TEST-CMD' "$CK11_ERR"; then
  ok "CK11 (R-06): touching .claude/test-cmd exits 4 and names TEST-CMD"
else
  bad "CK11 (R-06): test-cmd fixture returned $CK11_RC: $(cat "$CK11_ERR" 2>/dev/null)"
fi

CK12_REPO="$SCRATCH_ROOT/ck12_repo"; new_repo_empty "$CK12_REPO"
CK12_STUB="$SCRATCH_ROOT/ck12_stub"; mkdir -p "$CK12_STUB"
CK12_BEHAV="$SCRATCH_ROOT/ck12_behav"
mk_behav "$CK12_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CC_CD/tests"
printf 'def test_a():\n    pass\n' > "$CC_CD/tests/test_a.py"
exit 0
BEHAV_EOF
make_stub_codex "$CK12_STUB" ok "$CK12_BEHAV"
CK12_BRIEF="$SCRATCH_ROOT/ck12_brief"; printf 'brief\n' > "$CK12_BRIEF"
CK12_ERR="$SCRATCH_ROOT/ck12_err"
PATH="$CK12_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK12_REPO" --brief "$CK12_BRIEF" --out "$SCRATCH_ROOT/ck12_out" --model astra --effort medium >/dev/null 2>"$CK12_ERR"
CK12_RC=$?
if [ "$CK12_RC" -eq 4 ] && grep -qF 'TEST-FILE' "$CK12_ERR" && grep -qF 'tests/test_a.py' "$CK12_ERR"; then
  ok "CK12 (R-06): a new untracked test file exits 4 and names TEST-FILE plus its path"
else
  bad "CK12 (R-06): untracked-test fixture returned $CK12_RC: $(cat "$CK12_ERR" 2>/dev/null)"
fi
# plant: CK12 | plugin/scripts/codex-coder.sh | ls-files --others --exclude-standard | ls-files --cached

CK13_REPO="$SCRATCH_ROOT/ck13_repo"; new_repo_with_prod "$CK13_REPO"
CK13_STUB="$SCRATCH_ROOT/ck13_stub"; mkdir -p "$CK13_STUB"
CK13_BEHAV="$SCRATCH_ROOT/ck13_behav"
mk_behav "$CK13_BEHAV" <<'BEHAV_EOF'
printf 'print("modified")\n' > "$CC_CD/src/prod.py"
exit 0
BEHAV_EOF
make_stub_codex "$CK13_STUB" ok "$CK13_BEHAV"
CK13_BRIEF="$SCRATCH_ROOT/ck13_brief"; printf 'brief\n' > "$CK13_BRIEF"
CK13_ERR="$SCRATCH_ROOT/ck13_err"
PATH="$CK13_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK13_REPO" --brief "$CK13_BRIEF" --out "$SCRATCH_ROOT/ck13_out" --model astra --effort medium >/dev/null 2>"$CK13_ERR"
CK13_RC=$?
if [ "$CK13_RC" -eq 0 ]; then
  ok "CK13 (R-06): modifying only tracked production code exits 0"
else
  bad "CK13 (R-06): tracked-production fixture returned $CK13_RC: $(cat "$CK13_ERR" 2>/dev/null)"
fi

CK14_REPO="$SCRATCH_ROOT/ck14_repo"; new_repo_empty "$CK14_REPO"
CK14_STUB="$SCRATCH_ROOT/ck14_stub"; mkdir -p "$CK14_STUB"
CK14_BEHAV="$SCRATCH_ROOT/ck14_behav"
mk_behav "$CK14_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CC_CD/.claude/agent-memory/coder"
printf '# index\n' > "$CC_CD/.claude/agent-memory/coder/MEMORY.md"
exit 0
BEHAV_EOF
make_stub_codex "$CK14_STUB" ok "$CK14_BEHAV"
CK14_BRIEF="$SCRATCH_ROOT/ck14_brief"; printf 'brief\n' > "$CK14_BRIEF"
CK14_ERR="$SCRATCH_ROOT/ck14_err"
PATH="$CK14_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK14_REPO" --brief "$CK14_BRIEF" --out "$SCRATCH_ROOT/ck14_out" --model astra --effort medium >/dev/null 2>"$CK14_ERR"
CK14_RC=$?
if [ "$CK14_RC" -eq 4 ] && grep -qF 'MEMORY-INDEX' "$CK14_ERR"; then
  ok "CK14 (R-06): writing coder/MEMORY.md exits 4 and names MEMORY-INDEX"
else
  bad "CK14 (R-06): memory-index fixture returned $CK14_RC: $(cat "$CK14_ERR" 2>/dev/null)"
fi

CK15A_REPO="$SCRATCH_ROOT/ck15a_repo"; new_repo_empty "$CK15A_REPO"
CK15A_STUB="$SCRATCH_ROOT/ck15a_stub"; mkdir -p "$CK15A_STUB"
CK15A_BEHAV="$SCRATCH_ROOT/ck15a_behav"
mk_behav "$CK15A_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CC_CD/.claude/agent-memory/coder/topics"
printf 'a\n' > "$CC_CD/.claude/agent-memory/coder/topics/a.md"
printf 'b\n' > "$CC_CD/.claude/agent-memory/coder/topics/b.md"
exit 0
BEHAV_EOF
make_stub_codex "$CK15A_STUB" ok "$CK15A_BEHAV"
CK15A_BRIEF="$SCRATCH_ROOT/ck15a_brief"; printf 'brief\n' > "$CK15A_BRIEF"
CK15A_ERR="$SCRATCH_ROOT/ck15a_err"
PATH="$CK15A_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK15A_REPO" --brief "$CK15A_BRIEF" --out "$SCRATCH_ROOT/ck15a_out" --model astra --effort medium >/dev/null 2>"$CK15A_ERR"
CK15A_RC=$?

CK15B_REPO="$SCRATCH_ROOT/ck15b_repo"; new_repo_empty "$CK15B_REPO"
CK15B_STUB="$SCRATCH_ROOT/ck15b_stub"; mkdir -p "$CK15B_STUB"
CK15B_BEHAV="$SCRATCH_ROOT/ck15b_behav"
mk_behav "$CK15B_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CC_CD/.claude/agent-memory/coder/topics"
printf 'a\n' > "$CC_CD/.claude/agent-memory/coder/topics/a.md"
exit 0
BEHAV_EOF
make_stub_codex "$CK15B_STUB" ok "$CK15B_BEHAV"
CK15B_BRIEF="$SCRATCH_ROOT/ck15b_brief"; printf 'brief\n' > "$CK15B_BRIEF"
CK15B_ERR="$SCRATCH_ROOT/ck15b_err"
PATH="$CK15B_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK15B_REPO" --brief "$CK15B_BRIEF" --out "$SCRATCH_ROOT/ck15b_out" --model astra --effort medium >/dev/null 2>"$CK15B_ERR"
CK15B_RC=$?
if [ "$CK15A_RC" -eq 4 ] && grep -qF 'MEMORY-SHARDS' "$CK15A_ERR" && [ "$CK15B_RC" -eq 0 ]; then
  ok "CK15 (R-06): two new coder shards violate scope, exactly one does not"
else
  bad "CK15 (R-06): shard boundary gave two=$CK15A_RC one=$CK15B_RC: $(cat "$CK15A_ERR" "$CK15B_ERR" 2>/dev/null)"
fi

CK16_REPO="$SCRATCH_ROOT/ck16_repo"; new_repo_empty "$CK16_REPO"
CK16_STUB="$SCRATCH_ROOT/ck16_stub"; mkdir -p "$CK16_STUB"
CK16_BEHAV="$SCRATCH_ROOT/ck16_behav"
mk_behav "$CK16_BEHAV" <<'BEHAV_EOF'
printf 'changed\n' >> "$CC_CD/README.md"
git -C "$CC_CD" add README.md
git -C "$CC_CD" commit -qm codex-commit
exit 0
BEHAV_EOF
make_stub_codex "$CK16_STUB" ok "$CK16_BEHAV"
CK16_BRIEF="$SCRATCH_ROOT/ck16_brief"; printf 'brief\n' > "$CK16_BRIEF"
CK16_ERR="$SCRATCH_ROOT/ck16_err"
PATH="$CK16_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK16_REPO" --brief "$CK16_BRIEF" --out "$SCRATCH_ROOT/ck16_out" --model astra --effort medium >/dev/null 2>"$CK16_ERR"
CK16_RC=$?
if [ "$CK16_RC" -eq 4 ] && grep -qF 'NEW-COMMIT' "$CK16_ERR"; then
  ok "CK16 (R-06): a new worktree commit exits 4 and names NEW-COMMIT"
else
  bad "CK16 (R-06): new-commit fixture returned $CK16_RC: $(cat "$CK16_ERR" 2>/dev/null)"
fi
# plant: CK16 | plugin/scripts/codex-coder.sh | [ "$AFTER_HEAD" != "$BASELINE_HEAD" ] | [ "$AFTER_HEAD" != "$AFTER_HEAD" ]

CK17_N12=$(grep -oE 'touched-paths=[0-9]+' "$CK12_ERR" 2>/dev/null | head -1 | sed -E 's/touched-paths=//')
CK17_N13=$(grep -oE 'touched-paths=[0-9]+' "$CK13_ERR" 2>/dev/null | head -1 | sed -E 's/touched-paths=//')
case "$CK17_N12" in ''|*[!0-9]*) CK17_N12=-1 ;; esac
case "$CK17_N13" in ''|*[!0-9]*) CK17_N13=-1 ;; esac
if [ "$CK17_N12" -eq 1 ] && [ "$CK17_N13" -eq 1 ]; then
  ok "CK17 (R-06): script-reported touched-path populations are exactly 1 in CK12 and CK13"
else
  bad "CK17 (R-06): expected script-reported counts CK12=1 CK13=1, got $CK17_N12 and $CK17_N13"
fi

CK18_REPO="$SCRATCH_ROOT/ck18_repo"; new_repo_empty "$CK18_REPO"
CK18_STUB="$SCRATCH_ROOT/ck18_stub"; mkdir -p "$CK18_STUB"
CK18_BEHAV="$SCRATCH_ROOT/ck18_behav"; printf 'exit 0\n' > "$CK18_BEHAV"
make_stub_codex "$CK18_STUB" ok "$CK18_BEHAV"
CK18_BRIEF="$SCRATCH_ROOT/ck18_brief"; printf 'brief\n' > "$CK18_BRIEF"
CK18_ERR="$SCRATCH_ROOT/ck18_err"
PATH="$CK18_STUB:/usr/bin:/bin" "$real_bash" "$CC" --worktree "$CK18_REPO" --brief "$CK18_BRIEF" --out "$SCRATCH_ROOT/ck18_out" --model astra --effort medium >/dev/null 2>"$CK18_ERR"
CK18_RC=$?
if [ "$CK18_RC" -eq 0 ] && grep -qF 'codex-coder: NOTE:' "$CK18_ERR" \
   && grep -qF 'touched-paths=0' "$CK18_ERR"; then
  ok "CK18 (R-08): an empty write exits 0 and distinctly names the empty touched-path set"
else
  bad "CK18 (R-08): empty-write fixture returned $CK18_RC: $(cat "$CK18_ERR" 2>/dev/null)"
fi

# =====================================================================================
# Step 5 gate block.
CK19_HEADING='#### Codex coder backend for Step 5 dispatch (ADR-0196, both paths)'
CK19_COUNT=$(grep -cFx "$CK19_HEADING" "$STEP5")
if [ "$CK19_COUNT" -eq 1 ]; then
  ok "CK19 (R-01): the Codex coder backend heading exists exactly once"
else
  bad "CK19 (R-01): expected the Codex coder backend heading once, found $CK19_COUNT"
fi
# plant: CK19 | plugin/skills/concept-to-code/references/step5-implementation.md | #### Codex coder backend for Step 5 dispatch (ADR-0196, both paths) | #### REMOVED FOR PLANT

CK_GATE=$(slice_heading "$CK19_HEADING" "$STEP5")
CK20_CLAUDE=$(flat_regex_text "$CK_GATE" '\[claude-sonnet\]')
CK20_CODEX=$(flat_regex_text "$CK_GATE" '\[codex\]')
CK20_DEFAULT=$(flat_regex_text "$CK_GATE" 'claude-sonnet.{0,50}default|default.{0,50}claude-sonnet')
if [ "$CK20_CLAUDE" -eq 1 ] && [ "$CK20_CODEX" -eq 1 ] && [ "$CK20_DEFAULT" -eq 1 ]; then
  ok "CK20 (R-01): the gate offers claude-sonnet and codex, defaulting claude-sonnet"
else
  bad "CK20 (R-01): backend options/default are incomplete in the gate slice"
fi

CK21_ONCE=$(flat_count_text "$CK_GATE" 'one ask covers both')
CK21_BEFORE=$(flat_count_text "$CK_GATE" 'before the Workflow/Agent-tool branch')
CK21_TOOL=$(flat_count_text "$CK_GATE" 'AskUserQuestion')
if [ "$CK21_ONCE" -eq 1 ] && [ "$CK21_BEFORE" -eq 1 ] && [ "$CK21_TOOL" -eq 1 ]; then
  ok "CK21 (R-01): one ask fires before the branch and covers both dispatch paths"
else
  bad "CK21 (R-01): the single pre-branch ask clause is absent from the gate slice"
fi

CK22_MODEL=$(flat_regex_text "$CK_GATE" 'astra.{0,50}default.{0,80}sol|default.{0,50}astra.{0,80}sol')
CK22_EFFORT=$(flat_regex_text "$CK_GATE" 'medium.{0,50}default|default.{0,50}medium')
CK22_SAME_TURN=$(flat_regex_text "$CK_GATE" 'same gate turn.{0,120}(model.{0,120}effort|effort.{0,120}model)')
CK22_ALL=1
for _v in low medium high xhigh max ultra; do
  [ "$(flat_regex_text "$CK_GATE" "\\b$_v\\b")" -eq 1 ] || CK22_ALL=0
done
if [ "$CK22_MODEL" -eq 1 ] && [ "$CK22_EFFORT" -eq 1 ] && [ "$CK22_SAME_TURN" -eq 1 ] && [ "$CK22_ALL" -eq 1 ]; then
  ok "CK22 (R-02): the codex gate offers astra/sol and all six efforts with both defaults"
else
  bad "CK22 (R-02): model, effort vocabulary, or defaults are incomplete in the gate slice"
fi

CK23_REFIRE=$(flat_count_text "$CK_GATE" 're-fires on every Step 5 entry, fresh or resumed')
if [ "$CK23_REFIRE" -eq 1 ]; then
  ok "CK23 (R-03): the gate explicitly re-fires on every fresh or resumed Step 5 entry"
else
  bad "CK23 (R-03): the every-entry re-fire clause is absent from the gate slice"
fi

CK24_TOKEN_COUNT=$(grep -hFo 'step5_codex_coder_asked' "$STEP5" "$MINIT" "$MVALIDATE" | wc -l | tr -d ' ')
CK24_SKIP=$(flat_regex_text "$CK_GATE" 'if.{0,80}field.{0,40}true.{0,120}skip.{0,60}dispatch')
if [ "$CK19_COUNT" -eq 1 ] && [ "$CK24_TOKEN_COUNT" -eq 0 ] && [ "$CK24_SKIP" -eq 0 ]; then
  ok "CK24 (R-03): no asked field or field-true skip clause can suppress the gate"
else
  bad "CK24 (R-03): heading-count=$CK19_COUNT asked-token count=$CK24_TOKEN_COUNT skip-clause=$CK24_SKIP"
fi
# plant: CK24 | plugin/skills/concept-to-code/references/step5-implementation.md | The gate re-fires on every Step 5 entry, fresh or resumed. | If step5_codex_coder_asked is true, skip straight to dispatch.

# =====================================================================================
# Manifest fields and their shared vocabulary.
CK25_MISSING=""
grep -qF 'echo "use_codex_coder: false" >> "$T"' "$MINIT" || CK25_MISSING="$CK25_MISSING use_codex_coder"
grep -qF 'echo "step5_codex_coder_model: null" >> "$T"' "$MINIT" || CK25_MISSING="$CK25_MISSING step5_codex_coder_model"
grep -qF 'echo "step5_codex_coder_effort: null" >> "$T"' "$MINIT" || CK25_MISSING="$CK25_MISSING step5_codex_coder_effort"
if [ -z "$CK25_MISSING" ]; then
  ok "CK25 (R-10): manifest-init.sh carries all three exact coder seed lines"
else
  bad "CK25 (R-10): manifest-init.sh is missing:$CK25_MISSING"
fi
# plant: CK25 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "use_codex_coder: false" >> "$T" | :

CK26_ROOT="$SCRATCH_ROOT/ck26_root"; mkdir -p "$CK26_ROOT"
CK26_PATH=$("$MINIT" "ck26-$$" "CK26 test" "$CK26_ROOT" 2>/dev/null)
CK26_INIT_RC=$?
CK26_OK=1; CK26_MSG=""
if [ "$CK26_INIT_RC" -ne 0 ] || [ -z "$CK26_PATH" ] || [ ! -f "$CK26_PATH" ]; then
  CK26_OK=0; CK26_MSG=" init-failed"
else
  "$MVALIDATE" "$CK26_PATH" >/dev/null 2>&1 || { CK26_OK=0; CK26_MSG="$CK26_MSG initial-validation"; }
  grep -qFx 'manifest_schema_version: "1.4"' "$CK26_PATH" || { CK26_OK=0; CK26_MSG="$CK26_MSG schema-version"; }
  "$MSETFLAG" "$CK26_PATH" use_codex_coder true >/dev/null 2>&1 || { CK26_OK=0; CK26_MSG="$CK26_MSG set-flag"; }
  CK26_TMP="$SCRATCH_ROOT/ck26_tmp"
  sed 's/^step5_codex_coder_model: .*/step5_codex_coder_model: astra/; s/^step5_codex_coder_effort: .*/step5_codex_coder_effort: medium/' "$CK26_PATH" > "$CK26_TMP" && mv "$CK26_TMP" "$CK26_PATH"
  "$MVALIDATE" "$CK26_PATH" >/dev/null 2>&1 || { CK26_OK=0; CK26_MSG="$CK26_MSG valid-values"; }
  for _case in 'use_codex_coder maybe' 'step5_codex_coder_model terra' 'step5_codex_coder_effort banana'; do
    _field=${_case%% *}; _value=${_case#* }
    case "$_field" in
      use_codex_coder) _restore=true ;;
      step5_codex_coder_model) _restore=astra ;;
      step5_codex_coder_effort) _restore=medium ;;
    esac
    sed "s/^${_field}: .*/${_field}: ${_value}/" "$CK26_PATH" > "$CK26_TMP" && mv "$CK26_TMP" "$CK26_PATH"
    CK26_ERR=$("$MVALIDATE" "$CK26_PATH" 2>&1); CK26_RC=$?
    if [ "$CK26_RC" -eq 0 ] || ! printf '%s' "$CK26_ERR" | grep -qF "$_field"; then
      CK26_OK=0; CK26_MSG="$CK26_MSG invalid-not-named:${_field}"
    fi
    sed "s/^${_field}: .*/${_field}: ${_restore}/" "$CK26_PATH" > "$CK26_TMP" && mv "$CK26_TMP" "$CK26_PATH"
  done
fi
if [ "$CK26_OK" -eq 1 ]; then
  ok "CK26 (R-10): manifest init/set/validate round trip accepts valid values and names all invalid fields"
else
  bad "CK26 (R-10): end-to-end manifest contract failed:$CK26_MSG"
fi
# plant: CK26 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | fail "use_codex_coder field present but value is not 'true' or 'false'" | :

CK27_VALIDATOR=$(python3 -c '
import re, sys
for line in open(sys.argv[1]):
    if "grep -Eq" not in line or "step5_codex_coder_effort:" not in line:
        continue
    match = re.search(r"step5_codex_coder_effort: \(([^)]*)\)", line)
    if match:
        values = [v.strip(" \\\"\047") for v in match.group(1).split("|")]
        print(",".join(sorted(v for v in values if v != "null")))
        break
' "$MVALIDATE")
CK27_GATE=$(flat_regex_text "$CK_GATE" 'medium.{0,30}default.{0,120}low.{0,80}high.{0,80}xhigh.{0,80}max.{0,80}ultra|low.{0,80}medium.{0,80}high.{0,80}xhigh.{0,80}max.{0,80}ultra')
if [ "$CK27_VALIDATOR" = 'high,low,max,medium,ultra,xhigh' ] && [ "$CK27_GATE" -eq 1 ]; then
  ok "CK27 (R-10): Invariant 29 and the gate duplicate exactly the same six effort tokens"
else
  bad "CK27 (R-10): validator vocabulary='$CK27_VALIDATOR' gate-six=$CK27_GATE"
fi

# =====================================================================================
# Exit resolution and the two dispatch sites.
CK28_HEADING='#### Codex coder exit-code handling (ADR-0196)'
CK28_COUNT=$(grep -cFx "$CK28_HEADING" "$STEP5")
CK_EXIT=$(slice_heading "$CK28_HEADING" "$STEP5")
CK28_ALL=1
for _v in 0 2 3 4; do [ "$(flat_regex_text "$CK_EXIT" "exit $_v")" -eq 1 ] || CK28_ALL=0; done
if [ "$CK28_COUNT" -eq 1 ] && [ "$CK28_ALL" -eq 1 ]; then
  ok "CK28 (R-07): one exit-code section names exits 0, 2, 3, and 4"
else
  bad "CK28 (R-07): exit heading count=$CK28_COUNT all-four=$CK28_ALL"
fi

CK29_ASK=$(flat_count_text "$CK_EXIT" 'AskUserQuestion')
CK29_FALLBACK=$(flat_regex_text "$CK_EXIT" 'fallback')
CK29_ACCEPT=$(flat_regex_text "$CK_EXIT" 'accept')
CK29_HALT=$(flat_regex_text "$CK_EXIT" 'halt')
CK29_COMMIT=$(flat_regex_text "$CK_EXIT" 'new-commit')
if [ "$CK29_ASK" -eq 2 ] && [ "$CK29_FALLBACK" -eq 1 ] && [ "$CK29_ACCEPT" -eq 1 ] \
   && [ "$CK29_HALT" -eq 1 ] && [ "$CK29_COMMIT" -eq 1 ]; then
  ok "CK29 (R-07): exit 3/4 asks are explicit; exit 4 offers fallback/accept/halt and qualifies NEW-COMMIT"
else
  bad "CK29 (R-07): asks=$CK29_ASK fallback=$CK29_FALLBACK accept=$CK29_ACCEPT halt=$CK29_HALT new-commit=$CK29_COMMIT"
fi

CK30_NEEDLE='branch per `#### Codex coder exit-code handling` above (ADR-0196)'
CK30_COUNT=$(grep -cF -- "$CK30_NEEDLE" "$STEP5")
if [ "$CK30_COUNT" -eq 2 ]; then
  ok "CK30 (R-09): exactly two dispatch sites point to the shared coder exit-code section"
else
  bad "CK30 (R-09): expected two exit-code pointers, found $CK30_COUNT"
fi
# plant: CK30 | plugin/skills/concept-to-code/references/step5-implementation.md | branch per `#### Codex coder exit-code handling` above (ADR-0196), merge back via | continue to the merge-back block via

CK31_COUNT=$(grep -F '~/.claude/hooks/codex-coder.sh' "$STEP5" | grep -cF -- '--worktree')
if [ "$CK31_COUNT" -eq 2 ]; then
  ok "CK31 (R-09): exactly two invocation lines use the deployed hook path with --worktree"
else
  bad "CK31 (R-09): expected two deployed-path invocation lines, found $CK31_COUNT"
fi

CK_WORKFLOW=$(slice_heading '#### Workflow dispatch path — Step 5 implementation (hook_verified = true)' "$STEP5")
CK32_NO_STAGE=$(flat_regex_text "$CK_WORKFLOW" 'no coder stage.{0,80}pipeline|coder stage.{0,80}not.{0,40}pipeline')
CK32_LIVE=$(flat_regex_text "$CK_WORKFLOW" 'orchestrator.{0,40}own live turn.{0,100}sequential')
CK32_DEGENERATE=$(flat_regex_text "$CK_WORKFLOW" 'tester.{0,80}codex.{0,120}checkpoint.{0,120}no stages.{0,120}no workflow script')
if [ "$CK32_NO_STAGE" -eq 1 ] && [ "$CK32_LIVE" -eq 1 ] && [ "$CK32_DEGENERATE" -eq 1 ]; then
  ok "CK32 (R-09): Workflow codex dispatch is sequential, stage-free, and handles the empty pipeline"
else
  bad "CK32 (R-09): no-stage=$CK32_NO_STAGE live-sequential=$CK32_LIVE degenerate=$CK32_DEGENERATE"
fi

CK_AGENT=$(slice_heading '#### Fallback — Agent-tool batch dispatch (hook_verified = false or workflow unavailable)' "$STEP5")
CK33_FENCE=$(flat_regex_text "$CK_AGENT" 'completion-fact fence.{0,100}(not run|skip).{0,160}exit code.{0,80}completion fact')
CK33_MARKER='<!-- dispatch-site: step5-batch-coder class=isolated -->'
CK33_COUNT=$(grep -cFx "$CK33_MARKER" "$STEP5")
CK33_EXEMPT=$(grep -F "$CK33_MARKER" "$STEP5" | grep -cF 'exempt:')
if [ "$CK33_FENCE" -eq 1 ] && [ "$CK33_COUNT" -eq 1 ] && [ "$CK33_EXEMPT" -eq 0 ]; then
  ok "CK33 (R-09): Agent codex dispatch skips the fence and preserves one unexempted marker"
else
  bad "CK33 (R-09): fence-clause=$CK33_FENCE marker-count=$CK33_COUNT marker-exempt=$CK33_EXEMPT"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 33 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 33)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: assertion count fell to $_total (floor 33)"
  FAIL=$((FAIL+1))
fi

[ "$FAIL" -eq 0 ]
