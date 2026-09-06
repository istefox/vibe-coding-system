#!/bin/bash
# codex-tester-dispatch-gate.test.sh — ADR-0194.
# Plan: docs/superpowers/plans/2026-09-06-codex-claude-choice-for-tester.md
#
# Covers SPEC R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14.
# Assertion prefix CX verified free across staging/ on 2026-09-06 (plan "Read this first").
# Every assertion in this file is RED by construction until Tasks 2-6 land the implementation —
# a red CX section at the Batch A checkpoint is the deliverable, not a defect (Task 1; ADR-0101
# rule 1: an assertion must not share a batch with the task it depends on).
#
# Offline, hermetic, no network, no $HOME dependency, no live codex call — this repo's own
# convention (codex-reviewer-schema.test.sh states the same rule for its own file): never spend
# real Codex quota in CI. Behavioural assertions run codex-tester.sh against a stub `codex` on a
# scratch PATH, inside a scratch `git init` repository under `mktemp -d`.
# Bash 3.2 clean. Run: bash codex-tester-dispatch-gate.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
CT="$SCRIPTS/codex-tester.sh"
CR="$SCRIPTS/codex-reviewer.sh"
SYNC="$SCRIPTS/../../sync-to-claude.sh"
STEP5="$SCRIPTS/../skills/concept-to-code/references/step5-implementation.md"
MINIT="$SCRIPTS/../skills/concept-to-code/scripts/manifest-init.sh"
MVALIDATE="$SCRIPTS/../skills/concept-to-code/scripts/manifest-validate.sh"
MSETFLAG="$SCRIPTS/../skills/concept-to-code/scripts/manifest-set-flag.sh"
TESTER_MD="$SCRIPTS/../agents/tester.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# FATAL guard: everything this harness reads that is edited-in-place or a pre-existing sibling
# (never a NEW file this plan creates) must already exist. codex-tester.sh is deliberately
# EXCLUDED from this guard — CX01 below is the assertion that covers its absence, and a FATAL
# exit here would prevent every other CX id from ever reporting its own individual FAIL line.
for _f in "$SYNC" "$STEP5" "$MINIT" "$MVALIDATE" "$MSETFLAG" "$TESTER_MD" "$CR"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

real_bash=$(command -v bash)
SCRATCH_ROOT=$(mktemp -d)
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

# make_stub_codex <dir> <auth-status> <exec-behaviour-script>
# Writes an executable `codex` into <dir> that answers `doctor --json` with the given
# auth.credentials status and, on `exec`, runs <exec-behaviour-script> with the parsed
# -C/-o values in $CT_CD/$CT_OUT and records its own argv to <dir>/argv.txt.
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
    CT_CD=""
    CT_OUT=""
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        -C) CT_CD="\$2"; shift 2 ;;
        -o) CT_OUT="\$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    export CT_CD CT_OUT
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

# mk_behav <file> — writes stdin (a heredoc body) verbatim to <file>, for use as the third
# argument to make_stub_codex. $CT_CD / $CT_OUT are resolved when the behaviour script RUNS
# (inside the stub), not when it is written here — callers use a quoted heredoc terminator.
mk_behav() { cat > "$1"; }

# new_repo_empty <dir> — a scratch git repo with one commit (README.md only): no src/prod.py
# exists yet, so anything the exec-behaviour script writes under src/ is untracked/new.
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

# new_repo_with_prod <dir> — a scratch git repo with src/prod.py already tracked, so a later
# edit to it is a `git diff` modification, not an untracked/new path.
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

# flat_count_text <text> <needle> — rule 3: a clause is the same clause whether it wraps across
# lines, is backticked, is bolded, or opens a sentence. Strips `*_` decoration, collapses
# whitespace/newlines to single spaces, folds case, then counts substring occurrences.
flat_count_text() {
  python3 -c '
import re, sys
def flat(s):
    s = re.sub(r"[`*_]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.lower()
print(flat(sys.argv[1]).count(flat(sys.argv[2])))
' "$1" "$2"
}

# =====================================================================================
# A. The script exists, is deployed, and shells codex exec with the write-sandboxed flags
# (R-01, R-02). CX03/CX04 scope to the codex-exec invocation slice only (rule 1) — a needle
# matched against the whole file would be satisfied by this same header's own contrasting
# mention of `-s read-only` on codex-reviewer.sh.
if [ -f "$CT" ] && [ -r "$CT" ]; then
  ok "CX01 (R-01): staging/plugin/scripts/codex-tester.sh exists and is readable"
else
  bad "CX01 (R-01): staging/plugin/scripts/codex-tester.sh does not exist or is not readable"
fi

CX02_COUNT=$(grep -cF 'plugin/scripts/codex-tester.sh|hooks/codex-tester.sh' "$SYNC")
if [ "$CX02_COUNT" -eq 1 ]; then
  ok "CX02 (R-01): sync-to-claude.sh PAIRS carries the codex-tester.sh deploy line exactly once"
else
  bad "CX02 (R-01): expected exactly 1 PAIRS line 'plugin/scripts/codex-tester.sh|hooks/codex-tester.sh' in sync-to-claude.sh, found $CX02_COUNT"
fi
# plant: CX02 | sync-to-claude.sh | plugin/scripts/codex-tester.sh|hooks/codex-tester.sh | plugin/scripts/codex-tester.sh|hooks/codex-tester-REMOVED.sh

CX_INVOKE=$(awk '
  /^codex exec/ { grab=1 }
  grab { print; if ($0 !~ /\\$/) { exit } }
' "$CT" 2>/dev/null)

if printf '%s' "$CX_INVOKE" | grep -qF -- '-s workspace-write' && printf '%s' "$CX_INVOKE" | grep -qF -- '-C "$WORKTREE"'; then
  ok 'CX03 (R-02): codex exec invocation carries both -s workspace-write and -C "$WORKTREE"'
else
  bad "CX03 (R-02): codex exec invocation slice missing -s workspace-write and/or -C \"\$WORKTREE\" (slice: ${CX_INVOKE:-<empty — codex-tester.sh not found or has no codex exec line>})"
fi
# plant: CX03 | plugin/scripts/codex-tester.sh | -s workspace-write | -s read-only

if [ -z "$CX_INVOKE" ]; then
  bad "CX04 (R-02): codex exec invocation slice not found (codex-tester.sh missing or has no codex exec line) — cannot verify absence of danger-full-access/read-only"
elif printf '%s' "$CX_INVOKE" | grep -qF -- 'danger-full-access'; then
  bad "CX04 (R-02): codex exec invocation slice contains 'danger-full-access'"
elif printf '%s' "$CX_INVOKE" | grep -qF -- 'read-only'; then
  bad "CX04 (R-02): codex exec invocation slice contains 'read-only'"
else
  ok "CX04 (R-02): codex exec invocation slice names neither danger-full-access nor read-only"
fi

# =====================================================================================
# B. Availability cascade (R-03), behavioural, mirroring codex-reviewer.sh's own contract:
# no codex on PATH, or codex present but not authenticated, both exit 3 with a DID-NOT-RUN line.
CX05_DIR="$SCRATCH_ROOT/cx05_emptypath"
mkdir -p "$CX05_DIR"
CX05_RESOLVED=$(PATH="$CX05_DIR:/usr/bin:/bin" "$real_bash" -c 'command -v codex' 2>/dev/null || true)
if [ -n "$CX05_RESOLVED" ]; then
  bad "CX05 (R-03): DID-NOT-RUN — 'codex' unexpectedly resolved on the scratch PATH at $CX05_RESOLVED; cannot exercise the no-codex case"
else
  CX05_WT="$SCRATCH_ROOT/cx05_wt"; mkdir -p "$CX05_WT"
  CX05_BRIEF="$SCRATCH_ROOT/cx05_brief.txt"; printf 'brief\n' > "$CX05_BRIEF"
  CX05_OUT="$SCRATCH_ROOT/cx05_out.md"
  CX05_ERR="$SCRATCH_ROOT/cx05_err.txt"
  PATH="$CX05_DIR:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX05_WT" --brief "$CX05_BRIEF" --out "$CX05_OUT" >/dev/null 2>"$CX05_ERR"
  CX05_RC=$?
  if [ "$CX05_RC" -eq 3 ] && grep -qE '^codex-tester: DID-NOT-RUN:' "$CX05_ERR"; then
    ok "CX05 (R-03): no codex on PATH -> exit 3 with a ^codex-tester: DID-NOT-RUN: stderr line"
  else
    bad "CX05 (R-03): expected exit 3 + DID-NOT-RUN stderr, got exit $CX05_RC, stderr: $(cat "$CX05_ERR" 2>/dev/null)"
  fi
fi

CX06_STUB="$SCRATCH_ROOT/cx06_stub"; mkdir -p "$CX06_STUB"
CX06_BEHAV="$SCRATCH_ROOT/cx06_behav.sh"; printf 'exit 0\n' > "$CX06_BEHAV"
make_stub_codex "$CX06_STUB" error "$CX06_BEHAV"
CX06_WT="$SCRATCH_ROOT/cx06_wt"; mkdir -p "$CX06_WT"
CX06_BRIEF="$SCRATCH_ROOT/cx06_brief.txt"; printf 'brief\n' > "$CX06_BRIEF"
CX06_OUT="$SCRATCH_ROOT/cx06_out.md"
CX06_ERR="$SCRATCH_ROOT/cx06_err.txt"
PATH="$CX06_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX06_WT" --brief "$CX06_BRIEF" --out "$CX06_OUT" >/dev/null 2>"$CX06_ERR"
CX06_RC=$?
if [ "$CX06_RC" -eq 3 ] && grep -qF 'error' "$CX06_ERR"; then
  ok "CX06 (R-03): stub codex doctor auth.credentials.status=error -> exit 3, stderr names the status"
else
  bad "CX06 (R-03): expected exit 3 + stderr naming status 'error', got exit $CX06_RC, stderr: $(cat "$CX06_ERR" 2>/dev/null)"
fi

# =====================================================================================
# C. Post-run scope check (R-05) — the exit-4 contract, deliberately not derivable from
# `git diff --name-only` alone (ADR-0194 §Refinements R4: union of git diff, git diff --cached,
# and git ls-files --others --exclude-standard, against a pre-run baseline).
CX07_REPO="$SCRATCH_ROOT/cx07_repo"; new_repo_empty "$CX07_REPO"
CX07_STUB="$SCRATCH_ROOT/cx07_stub"; mkdir -p "$CX07_STUB"
CX07_BEHAV="$SCRATCH_ROOT/cx07_behav.sh"
mk_behav "$CX07_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CT_CD/src" "$CT_CD/tests"
printf 'print("new")\n' > "$CT_CD/src/prod.py"
printf 'def test_a():\n    pass\n' > "$CT_CD/tests/test_a.py"
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"tests/test_a.py","run_result":"1 passed","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"R-05","sub_steps":"n/a"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX07_STUB" ok "$CX07_BEHAV"
CX07_BRIEF="$SCRATCH_ROOT/cx07_brief.txt"; printf 'brief\n' > "$CX07_BRIEF"
CX07_OUT="$SCRATCH_ROOT/cx07_out.md"
CX07_ERR="$SCRATCH_ROOT/cx07_err.txt"
PATH="$CX07_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX07_REPO" --brief "$CX07_BRIEF" --out "$CX07_OUT" >/dev/null 2>"$CX07_ERR"
CX07_RC=$?
if [ "$CX07_RC" -eq 4 ] && grep -qF 'src/prod.py' "$CX07_ERR"; then
  ok "CX07 (R-05): new untracked src/prod.py + tests/test_a.py -> exit 4, src/prod.py named on stderr"
else
  bad "CX07 (R-05): expected exit 4 with src/prod.py on stderr, got exit $CX07_RC, stderr: $(cat "$CX07_ERR" 2>/dev/null)"
fi
# plant: CX07 | plugin/scripts/codex-tester.sh | ls-files --others --exclude-standard | ls-files --cached

CX08_REPO="$SCRATCH_ROOT/cx08_repo"; new_repo_empty "$CX08_REPO"
CX08_STUB="$SCRATCH_ROOT/cx08_stub"; mkdir -p "$CX08_STUB"
CX08_BEHAV="$SCRATCH_ROOT/cx08_behav.sh"
mk_behav "$CX08_BEHAV" <<'BEHAV_EOF'
mkdir -p "$CT_CD/tests"
printf 'def test_a():\n    pass\n' > "$CT_CD/tests/test_a.py"
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"tests/test_a.py","run_result":"1 passed","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"R-05","sub_steps":"n/a"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX08_STUB" ok "$CX08_BEHAV"
CX08_BRIEF="$SCRATCH_ROOT/cx08_brief.txt"; printf 'brief\n' > "$CX08_BRIEF"
CX08_OUT="$SCRATCH_ROOT/cx08_out.md"
CX08_ERR="$SCRATCH_ROOT/cx08_err.txt"
PATH="$CX08_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX08_REPO" --brief "$CX08_BRIEF" --out "$CX08_OUT" >/dev/null 2>"$CX08_ERR"
CX08_RC=$?
if [ "$CX08_RC" -eq 0 ] && [ -s "$CX08_OUT" ]; then
  ok "CX08 (R-05): writing only tests/test_a.py -> exit 0, --out non-empty"
else
  bad "CX08 (R-05): expected exit 0 with non-empty --out, got exit $CX08_RC, out-size=$([ -f "$CX08_OUT" ] && wc -c < "$CX08_OUT" || echo 0)"
fi

# CX09: count guard on the derived population (rule 7) — read from the script's OWN stderr
# summary line (never re-derived in the harness, so the two derivations cannot disagree).
# Contract assumed by this harness (undocumented elsewhere): codex-tester.sh emits, on stderr,
# a line matching `codex-tester: touched-paths=<N>: <paths or (none)>` on every run.
CX09_N7=$(grep -oE 'touched-paths=[0-9]+' "$CX07_ERR" 2>/dev/null | head -1 | sed -E 's/touched-paths=//')
CX09_N8=$(grep -oE 'touched-paths=[0-9]+' "$CX08_ERR" 2>/dev/null | head -1 | sed -E 's/touched-paths=//')
case "$CX09_N7" in ''|*[!0-9]*) CX09_N7=-1 ;; esac
case "$CX09_N8" in ''|*[!0-9]*) CX09_N8=-1 ;; esac
if [ "$CX09_N7" -eq 2 ] && [ "$CX09_N8" -eq 1 ]; then
  ok "CX09 (R-05): touched-path set size is exactly 2 in the CX07 fixture and exactly 1 in the CX08 fixture (read from the script's own stderr)"
else
  bad "CX09 (R-05): expected touched-paths=2 (CX07 fixture) and touched-paths=1 (CX08 fixture); found CX07=$CX09_N7 CX08=$CX09_N8 (or no summary line at all)"
fi

CX10_REPO="$SCRATCH_ROOT/cx10_repo"; new_repo_with_prod "$CX10_REPO"
CX10_STUB="$SCRATCH_ROOT/cx10_stub"; mkdir -p "$CX10_STUB"
CX10_BEHAV="$SCRATCH_ROOT/cx10_behav.sh"
mk_behav "$CX10_BEHAV" <<'BEHAV_EOF'
printf 'print("modified")\n' > "$CT_CD/src/prod.py"
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"none","run_result":"n/a","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"R-05","sub_steps":"n/a"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX10_STUB" ok "$CX10_BEHAV"
CX10_BRIEF="$SCRATCH_ROOT/cx10_brief.txt"; printf 'brief\n' > "$CX10_BRIEF"
CX10_OUT="$SCRATCH_ROOT/cx10_out.md"
CX10_ERR="$SCRATCH_ROOT/cx10_err.txt"
PATH="$CX10_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX10_REPO" --brief "$CX10_BRIEF" --out "$CX10_OUT" >/dev/null 2>"$CX10_ERR"
CX10_RC=$?
if [ "$CX10_RC" -eq 4 ]; then
  ok "CX10 (R-05): modifying an already-tracked src/prod.py -> exit 4 (the git-diff half of the union)"
else
  bad "CX10 (R-05): expected exit 4 for a modified already-tracked src/prod.py, got exit $CX10_RC, stderr: $(cat "$CX10_ERR" 2>/dev/null)"
fi

CX11_REPO="$SCRATCH_ROOT/cx11_repo"; new_repo_empty "$CX11_REPO"
CX11_STUB="$SCRATCH_ROOT/cx11_stub"; mkdir -p "$CX11_STUB"
CX11_BEHAV="$SCRATCH_ROOT/cx11_behav.sh"
mk_behav "$CX11_BEHAV" <<'BEHAV_EOF'
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"none","run_result":"n/a","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"none","sub_steps":"none"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX11_STUB" ok "$CX11_BEHAV"
CX11_BRIEF="$SCRATCH_ROOT/cx11_brief.txt"; printf 'brief\n' > "$CX11_BRIEF"
CX11_OUT="$SCRATCH_ROOT/cx11_out.md"
CX11_ERR="$SCRATCH_ROOT/cx11_err.txt"
PATH="$CX11_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX11_REPO" --brief "$CX11_BRIEF" --out "$CX11_OUT" >/dev/null 2>"$CX11_ERR"
CX11_RC=$?
if [ "$CX11_RC" -eq 0 ] && grep -qF 'codex-tester: NOTE:' "$CX11_ERR"; then
  ok "CX11 (R-05): writing nothing -> exit 0 plus a codex-tester: NOTE: line naming the empty touched-path set"
else
  bad "CX11 (R-05): expected exit 0 + a codex-tester: NOTE: stderr line for an empty write, got exit $CX11_RC, stderr: $(cat "$CX11_ERR" 2>/dev/null)"
fi

# =====================================================================================
# D. --effort passthrough (R-06): present -> `-c model_reasoning_effort=<value>`; absent ->
# no model_reasoning_effort substring at all (config.toml governs, never an empty value).
CX12_REPO="$SCRATCH_ROOT/cx12_repo"; new_repo_empty "$CX12_REPO"
CX12_STUB="$SCRATCH_ROOT/cx12_stub"; mkdir -p "$CX12_STUB"
CX12_BEHAV="$SCRATCH_ROOT/cx12_behav.sh"
mk_behav "$CX12_BEHAV" <<'BEHAV_EOF'
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"none","run_result":"n/a","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"none","sub_steps":"none"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX12_STUB" ok "$CX12_BEHAV"
CX12_BRIEF="$SCRATCH_ROOT/cx12_brief.txt"; printf 'brief\n' > "$CX12_BRIEF"
CX12_OUT="$SCRATCH_ROOT/cx12_out.md"
PATH="$CX12_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX12_REPO" --brief "$CX12_BRIEF" --out "$CX12_OUT" --effort high >/dev/null 2>/dev/null
if [ -s "$CX12_STUB/argv.txt" ] && grep -qF -- '-c model_reasoning_effort=high' "$CX12_STUB/argv.txt"; then
  ok "CX12 (R-06): --effort high is passed through to codex exec as -c model_reasoning_effort=high"
else
  bad "CX12 (R-06): -c model_reasoning_effort=high not found in the stub's recorded argv ($([ -f "$CX12_STUB/argv.txt" ] && cat "$CX12_STUB/argv.txt" || echo 'argv.txt not written — codex exec likely never ran'))"
fi

CX13_REPO="$SCRATCH_ROOT/cx13_repo"; new_repo_empty "$CX13_REPO"
CX13_STUB="$SCRATCH_ROOT/cx13_stub"; mkdir -p "$CX13_STUB"
CX13_BEHAV="$SCRATCH_ROOT/cx13_behav.sh"
mk_behav "$CX13_BEHAV" <<'BEHAV_EOF'
cat > "$CT_OUT" <<'JSON_EOF'
{"tests_added":"none","run_result":"n/a","coverage":"n/a","bugs_found":"none","requirement_ids_covered":"none","sub_steps":"none"}
JSON_EOF
exit 0
BEHAV_EOF
make_stub_codex "$CX13_STUB" ok "$CX13_BEHAV"
CX13_BRIEF="$SCRATCH_ROOT/cx13_brief.txt"; printf 'brief\n' > "$CX13_BRIEF"
CX13_OUT="$SCRATCH_ROOT/cx13_out.md"
PATH="$CX13_STUB:/usr/bin:/bin" "$real_bash" "$CT" --worktree "$CX13_REPO" --brief "$CX13_BRIEF" --out "$CX13_OUT" >/dev/null 2>/dev/null
if [ -s "$CX13_STUB/argv.txt" ] && ! grep -qF 'model_reasoning_effort' "$CX13_STUB/argv.txt"; then
  ok "CX13 (R-06): no --effort given -> recorded argv contains no model_reasoning_effort substring at all"
else
  bad "CX13 (R-06): expected argv.txt with no model_reasoning_effort substring, got: $([ -f "$CX13_STUB/argv.txt" ] && cat "$CX13_STUB/argv.txt" || echo 'argv.txt not written — codex exec likely never ran')"
fi

# =====================================================================================
# E. Bad invocations (R-03) all exit 2 — four sub-checks, one assertion id.
CX14_WT="$SCRATCH_ROOT/cx14_wt"; mkdir -p "$CX14_WT"
CX14_DIR="$SCRATCH_ROOT/cx14_unreadable_dir"; mkdir -p "$CX14_DIR"
CX14_BRIEF="$SCRATCH_ROOT/cx14_brief.txt"; printf 'brief\n' > "$CX14_BRIEF"
CX14_OUT="$SCRATCH_ROOT/cx14_out.md"
CX14_STUB="$SCRATCH_ROOT/cx14_stub"; mkdir -p "$CX14_STUB"
CX14_BEHAV="$SCRATCH_ROOT/cx14_behav.sh"; printf 'exit 0\n' > "$CX14_BEHAV"
make_stub_codex "$CX14_STUB" ok "$CX14_BEHAV"
cx14_case() {
  PATH="$CX14_STUB:/usr/bin:/bin" "$real_bash" "$CT" "$@" >/dev/null 2>/dev/null
  [ "$?" -eq 2 ]
}
CX14_FAILS=""
cx14_case --bogus-flag --worktree "$CX14_WT" --brief "$CX14_BRIEF" --out "$CX14_OUT" || CX14_FAILS="$CX14_FAILS unknown-flag"
cx14_case --brief "$CX14_BRIEF" --out "$CX14_OUT" || CX14_FAILS="$CX14_FAILS missing---worktree"
cx14_case --worktree "$CX14_WT" --brief "$CX14_BRIEF" || CX14_FAILS="$CX14_FAILS missing---out"
cx14_case --worktree "$CX14_WT" --brief "$CX14_DIR" --out "$CX14_OUT" || CX14_FAILS="$CX14_FAILS unreadable---brief"
if [ -z "$CX14_FAILS" ]; then
  ok "CX14 (R-03): all 4 bad-invocation cases exit 2 (unknown flag, missing --worktree, missing --out, unreadable --brief)"
else
  bad "CX14 (R-03): bad-invocation case(s) did not exit 2:$CX14_FAILS"
fi

# =====================================================================================
# F. Drift guard (R-03, ADR-0194 §Refinements R7): the availability cascade's rate-limit
# vocabulary and the non-empty-output-outranks-the-grep precedence check (VCS-064) must be
# byte-identical in both codex-reviewer.sh and codex-tester.sh — exactly the kind of fix that
# gets applied to one copy and not the other.
CX15_NEEDLE_REGEX='usage limit|rate limit|quota exceeded|\b429\b'
CX15_NEEDLE_PRECEDENCE='[ -s "$RAW_OUT" ]'
CR_HAS_REGEX=0; grep -qF -- "$CX15_NEEDLE_REGEX" "$CR" && CR_HAS_REGEX=1
CT_HAS_REGEX=0; grep -qF -- "$CX15_NEEDLE_REGEX" "$CT" 2>/dev/null && CT_HAS_REGEX=1
CR_HAS_PREC=0; grep -qF -- "$CX15_NEEDLE_PRECEDENCE" "$CR" && CR_HAS_PREC=1
CT_HAS_PREC=0; grep -qF -- "$CX15_NEEDLE_PRECEDENCE" "$CT" 2>/dev/null && CT_HAS_PREC=1
if [ "$CR_HAS_REGEX" -eq 1 ] && [ "$CT_HAS_REGEX" -eq 1 ] && [ "$CR_HAS_PREC" -eq 1 ] && [ "$CT_HAS_PREC" -eq 1 ]; then
  ok 'CX15 (R-03): rate-limit regex and [ -s "$RAW_OUT" ] precedence check are byte-identical in both codex-reviewer.sh and codex-tester.sh'
else
  bad "CX15 (R-03): drift — codex-reviewer.sh regex=$CR_HAS_REGEX precedence=$CR_HAS_PREC; codex-tester.sh regex=$CT_HAS_REGEX precedence=$CT_HAS_PREC (both scripts must carry both, byte-identical)"
fi
# plant: CX15 | plugin/scripts/codex-tester.sh | usage limit|rate limit|quota exceeded|\b429\b | usage limit|rate limit

# =====================================================================================
# G. Manifest seeding and validation (R-10, R-11).
if grep -qF 'echo "use_codex_tester: false" >> "$T"' "$MINIT"; then
  ok "CX16 (R-10): manifest-init.sh seeds use_codex_tester: false"
else
  bad "CX16 (R-10): manifest-init.sh does not seed use_codex_tester: false"
fi
# plant: CX16 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "use_codex_tester: false" >> "$T" | :

if grep -qF 'echo "step5_codex_tester_asked: false" >> "$T"' "$MINIT"; then
  ok "CX17 (R-10): manifest-init.sh seeds step5_codex_tester_asked: false"
else
  bad "CX17 (R-10): manifest-init.sh does not seed step5_codex_tester_asked: false"
fi

CX18_ROOT="$SCRATCH_ROOT/cx18_root"; mkdir -p "$CX18_ROOT"
CX18_TOPIC="cxtest-$$"
CX18_MPATH=$("$MINIT" "$CX18_TOPIC" "CX18 test" "$CX18_ROOT" 2>/dev/null)
CX18_INIT_RC=$?
if [ "$CX18_INIT_RC" -ne 0 ] || [ -z "$CX18_MPATH" ] || [ ! -f "$CX18_MPATH" ]; then
  bad "CX18 (R-11): manifest-init.sh did not produce a manifest to validate (rc=$CX18_INIT_RC)"
else
  CX18_STEPS_OK=1
  CX18_MSG=""

  "$MVALIDATE" "$CX18_MPATH" >/dev/null 2>&1 || { CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG initial-validate-failed"; }

  grep -qF 'manifest_schema_version: "1.4"' "$CX18_MPATH" || { CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG schema-not-1.4"; }

  for _field in use_codex_tester step5_codex_tester_asked; do
    "$MSETFLAG" "$CX18_MPATH" "$_field" true >/dev/null 2>&1 || { CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG set-true-failed:$_field"; }
    "$MVALIDATE" "$CX18_MPATH" >/dev/null 2>&1 || { CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG revalidate-after-true-failed:$_field"; }
  done

  for _field in use_codex_tester step5_codex_tester_asked; do
    CX18_TMP=$(mktemp)
    sed "s/^${_field}: .*/${_field}: maybe/" "$CX18_MPATH" > "$CX18_TMP" && mv "$CX18_TMP" "$CX18_MPATH"
    CX18_VALIDATE_OUT=$("$MVALIDATE" "$CX18_MPATH" 2>&1)
    CX18_VALIDATE_RC=$?
    if [ "$CX18_VALIDATE_RC" -eq 0 ]; then
      CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG maybe-not-rejected:$_field"
    elif ! printf '%s' "$CX18_VALIDATE_OUT" | grep -qF "$_field"; then
      CX18_STEPS_OK=0; CX18_MSG="$CX18_MSG maybe-rejected-but-field-not-named:$_field"
    fi
    CX18_TMP2=$(mktemp)
    sed "s/^${_field}: maybe/${_field}: true/" "$CX18_MPATH" > "$CX18_TMP2" && mv "$CX18_TMP2" "$CX18_MPATH"
  done

  if [ "$CX18_STEPS_OK" -eq 1 ]; then
    ok "CX18 (R-11): manifest-init/validate/set-flag round trip for use_codex_tester and step5_codex_tester_asked (Invariants 26/27), schema stays 1.4"
  else
    bad "CX18 (R-11): round trip failed —$CX18_MSG"
  fi
fi
# plant: CX18 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | fail "use_codex_tester field present but value is not 'true' or 'false'" | :

# =====================================================================================
# H. Step 5 ask block, both dispatch paths (R-07, R-08, R-12).
CX19_HEADING='#### Codex tester backend for Step 5 dispatch (ADR-0194, both paths)'
CX19_COUNT=$(grep -cFx "$CX19_HEADING" "$STEP5")
if [ "$CX19_COUNT" -eq 1 ]; then
  ok "CX19 (R-07, R-08): step5-implementation.md carries the Codex tester backend heading exactly once"
else
  bad "CX19 (R-07, R-08): expected exactly 1 occurrence of the heading '$CX19_HEADING', found $CX19_COUNT"
fi
# plant: CX19 | plugin/skills/concept-to-code/references/step5-implementation.md | #### Codex tester backend for Step 5 dispatch (ADR-0194, both paths) | #### REMOVED FOR PLANT

CX20_BLOCK=$(awk -v h="$CX19_HEADING" '
  $0 == h { grab=1; next }
  grab && /^#### / { exit }
  grab { print }
' "$STEP5")

if printf '%s' "$CX20_BLOCK" | grep -qF 'claude-sonnet' \
   && printf '%s' "$CX20_BLOCK" | grep -qF 'codex' \
   && printf '%s' "$CX20_BLOCK" | grep -qF 'claude-opus'; then
  ok "CX20 (R-07, R-08): the Codex tester backend block's ask offers claude-sonnet, codex, and claude-opus"
else
  bad "CX20 (R-07, R-08): the Codex tester backend block is missing, or does not offer all three of claude-sonnet/codex/claude-opus inside its slice"
fi

CX21_COUNT=$(flat_count_text "$CX20_BLOCK" 'before the Workflow/Agent-tool branch, so one ask covers both')
if [ "$CX21_COUNT" -ge 1 ]; then
  ok "CX21 (R-07, R-08): the ask fires once, before the Workflow/Agent-tool branch, covering both dispatch paths"
else
  bad "CX21 (R-07, R-08): no clause found stating the ask fires once before the Workflow/Agent-tool branch"
fi

CX22_COUNT=$(flat_count_text "$CX20_BLOCK" 'skipped under --autopilot')
if [ "$CX22_COUNT" -ge 1 ]; then
  ok "CX22 (R-07, R-08): an autopilot-skip clause is present in the ask block"
else
  bad "CX22 (R-07, R-08): no autopilot-skip clause found in the ask block"
fi

CX23_A=$(flat_count_text "$CX20_BLOCK" 'Gate on `manifest.step5_codex_tester_asked`, not on `use_codex_tester` itself')
CX23_B=$(flat_count_text "$CX20_BLOCK" 'step5_codex_tester_asked: true` regardless of the answer')
if [ "$CX23_A" -ge 1 ] && [ "$CX23_B" -ge 1 ]; then
  ok "CX23 (R-12): the block gates on step5_codex_tester_asked (not use_codex_tester alone) and states the write is unconditional on the answer"
else
  bad "CX23 (R-12): missing gate-on-asked clause (found=$CX23_A) and/or unconditional-write clause (found=$CX23_B)"
fi

# =====================================================================================
# I. Exit-code handling section, both dispatch sites (R-09, R-01).
CX24_HEADING='#### Codex tester exit-code handling (ADR-0194)'
CX24_COUNT=$(grep -cFx "$CX24_HEADING" "$STEP5")
CX24_BLOCK=$(awk -v h="$CX24_HEADING" '
  $0 == h { grab=1; next }
  grab && /^#### / { exit }
  grab { print }
' "$STEP5")
CX24_HAS_0=$(flat_count_text "$CX24_BLOCK" 'exit 0')
CX24_HAS_2=$(flat_count_text "$CX24_BLOCK" 'exit 2')
CX24_HAS_3=$(flat_count_text "$CX24_BLOCK" 'exit 3')
CX24_HAS_4=$(flat_count_text "$CX24_BLOCK" 'exit 4')
if [ "$CX24_COUNT" -eq 1 ] && [ "$CX24_HAS_0" -ge 1 ] && [ "$CX24_HAS_2" -ge 1 ] && [ "$CX24_HAS_3" -ge 1 ] && [ "$CX24_HAS_4" -ge 1 ]; then
  ok "CX24 (R-09): the exit-code handling section exists exactly once and names all four of exit 0/2/3/4"
else
  bad "CX24 (R-09): heading count=$CX24_COUNT (want 1); exit-0=$CX24_HAS_0 exit-2=$CX24_HAS_2 exit-3=$CX24_HAS_3 exit-4=$CX24_HAS_4 (want >=1 each)"
fi

CX25_ASK_COUNT=$(flat_count_text "$CX24_BLOCK" 'AskUserQuestion')
CX25_HAS_FALLBACK=$(flat_count_text "$CX24_BLOCK" 'fallback')
CX25_HAS_ACCEPT=$(flat_count_text "$CX24_BLOCK" 'accept')
CX25_HAS_HALT=$(flat_count_text "$CX24_BLOCK" 'halt')
if [ "$CX25_ASK_COUNT" -ge 2 ] && [ "$CX25_HAS_FALLBACK" -ge 1 ] && [ "$CX25_HAS_ACCEPT" -ge 1 ] && [ "$CX25_HAS_HALT" -ge 1 ]; then
  ok "CX25 (R-09): exit-3 and exit-4 branches each carry an AskUserQuestion, and exit-4 offers fallback/accept/halt"
else
  bad "CX25 (R-09): AskUserQuestion count=$CX25_ASK_COUNT (want >=2); fallback=$CX25_HAS_FALLBACK accept=$CX25_HAS_ACCEPT halt=$CX25_HAS_HALT (want >=1 each)"
fi

CX26_NEEDLE='branch per `#### Codex tester exit-code handling` above (ADR-0194)'
CX26_COUNT=$(grep -cF -- "$CX26_NEEDLE" "$STEP5")
if [ "$CX26_COUNT" -eq 2 ]; then
  ok "CX26 (R-09): exactly 2 dispatch sites point back at the Codex tester exit-code handling section"
else
  bad "CX26 (R-09): expected exactly 2 occurrences of the pointer literal, found $CX26_COUNT"
fi
# plant: CX26 | plugin/skills/concept-to-code/references/step5-implementation.md | branch per `#### Codex tester exit-code handling` above (ADR-0194) | branch as documented above (ADR-0194)

CX27_COUNT=$(grep -F '~/.claude/hooks/codex-tester.sh' "$STEP5" | grep -cF -- '--worktree')
if [ "$CX27_COUNT" -eq 2 ]; then
  ok "CX27 (R-09, R-01): exactly 2 lines name the deployed hooks/codex-tester.sh path together with --worktree"
else
  bad "CX27 (R-09, R-01): expected exactly 2 lines naming ~/.claude/hooks/codex-tester.sh with --worktree, found $CX27_COUNT"
fi

# =====================================================================================
# J. Effort pin lowering, three sites (R-13, R-14; ADR-0194 §Refinements R6).
CX28_FRONTMATTER=$(awk '
  NR==1 && $0=="---" { grab=1; next }
  grab && $0=="---" { exit }
  grab { print }
' "$TESTER_MD")
if printf '%s\n' "$CX28_FRONTMATTER" | grep -qFx 'effort: high'; then
  ok "CX28 (R-13): tester.md frontmatter reads 'effort: high' exactly"
else
  bad "CX28 (R-13): tester.md frontmatter does not contain the exact line 'effort: high' (currently: $(printf '%s' "$CX28_FRONTMATTER" | grep '^effort:' || echo 'no effort: line found'))"
fi

CX29_HAS_HIGH=0; grep -qF 'effort: "high"' "$STEP5" && CX29_HAS_HIGH=1
CX29_XHIGH_COUNT=$(grep -cF 'effort: "xhigh"' "$STEP5")
if [ "$CX29_HAS_HIGH" -eq 1 ] && [ "$CX29_XHIGH_COUNT" -eq 0 ]; then
  ok 'CX29 (R-14): the Workflow tester pin reads effort: "high" and effort: "xhigh" is gone from step5-implementation.md'
else
  bad "CX29 (R-14): effort: \"high\" present=$CX29_HAS_HIGH (want 1); effort: \"xhigh\" occurrences=$CX29_XHIGH_COUNT (want 0)"
fi
# plant: CX29 | plugin/skills/concept-to-code/references/step5-implementation.md | effort: "high" | effort: "xhigh"

CX30_TABLE_ROW_HAS_TESTER=0
grep -qF '| `architect`, `coder`, `tester` | `xhigh` |' "$STEP5" && CX30_TABLE_ROW_HAS_TESTER=1
CX30_TMPL_COUNT=$(flat_count_text "$(cat "$STEP5")" 'no `effort` pin — the Agent tool has no such parameter')
CX30_TEMPLATE_STATES_NO_EFFORT=0
[ "$CX30_TMPL_COUNT" -ge 1 ] && CX30_TEMPLATE_STATES_NO_EFFORT=1
if [ "$CX30_TABLE_ROW_HAS_TESTER" -eq 0 ] && [ "$CX30_TEMPLATE_STATES_NO_EFFORT" -eq 1 ]; then
  ok "CX30 (R-14): the effort table no longer lists tester on its xhigh row, and the Tester batch dispatch template still states no effort is pinned there"
else
  bad "CX30 (R-14): effort-table still lists tester on its xhigh row=$CX30_TABLE_ROW_HAS_TESTER (want 0); template no-effort clause present=$CX30_TEMPLATE_STATES_NO_EFFORT (want 1)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 30 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 30)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: assertion count fell to $_total (floor 30) — assertions vanished"
  FAIL=$((FAIL+1))
fi

[ "$FAIL" -eq 0 ]
