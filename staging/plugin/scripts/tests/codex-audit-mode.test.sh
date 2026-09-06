#!/bin/bash
# codex-audit-mode.test.sh — offline, hermetic, no network, no $HOME dependency, NEVER a live
# `codex` call (this repo's standing rule: CI never spends real Codex quota — every `codex`
# invocation below hits a stub built on an isolated PATH inside a mktemp -d, never the real CLI).
# Bash 3.2 clean. Run: bash codex-audit-mode.test.sh
#
# Feature: 2026-09-05-codex-review-gate-deep-refactor.md — ADR-0193
# (`docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md`). Both literals are stated here
# per ADR-0154 §D1: this file's own text must name the plan's basename or one of the ADR ids the
# plan cites, or `spec-coverage.sh`'s back-reference scope filter drops this harness and every
# R-NN id below reports UNSCOPED rather than COVERED.
#
# Covers SPEC.md's eleven directly-testable requirement ids, individually cited beside the CX
# blocks below that assert them. SPEC.md itself marks three of its fourteen declared ids
# `(no-test: ...)` — two plant-existence ids and one ADR/documentation id — and this file
# deliberately never writes any of those three as a literal token — spec-coverage.sh's own
# STALE-WAIVER check (ADR-0154 §D8) treats a waived id's token appearing in a scoped test file as
# the waiver no longer protecting anything, which would block the Step 5 -> Step 6 gate for no
# reason connected to this feature's actual state.
#
# Section prefix `CX` was verified free across staging/ + docs/ + .github/ on 2026-09-05 (0 prior
# occurrences) before this file was written.
#
# STATE AT AUTHORING (rule 13 — re-derive, do not trust): this file is written BEFORE Tasks 2-8
# land any of the code or skill-prose it exercises (ADR-0049 spec-first dispatch — the tester is
# briefed from the plan, never from an implementation that does not yet exist). Measured by
# actually running this file on 2026-09-05, before any of Tasks 2-8:
#   - CX01, CX02, CX06, CX08, CX09, CX10, CX11, CX12, CX13, CX14, CX15, CX17, CX18, CX19, CX20,
#     CX22, CX23 and CX24 are RED by construction today. Tasks 2-8 turn them GREEN one at a time;
#     see the plan's own per-task "`CXnn` go(es) green here" notes for which task flips which id.
#   - CX07, CX25, CX26 and CX27 are GREEN from this Batch A checkpoint onward: they pin BEHAVIOUR
#     THAT ALREADY EXISTS (the two untouched codex-reviewer.sh modes, the deep-refactor dimension
#     table and finding-schema fence, ADR-0187's own historical text, and — measured 2026-09-05 —
#     ADR-0193 plus its chain-decision-index entry, both already on disk). A RED here at any later
#     checkpoint means a later task broke something it was told not to touch, not that the feature
#     is incomplete.
#   - CX03, CX04, CX05, CX16 and CX21 also read GREEN today, ahead of their nominal task, and this
#     is not a bug: CX03/CX04/CX05 each probe a bad-invocation shape that codex-reviewer.sh's
#     existing flag parser already rejects with exit 2 (today for the generic "audit isn't a known
#     mode/argument" reason, post-Task-2 for the specific reason each assertion names) — the
#     external contract they check does not change underneath them. CX16 and CX21 check facts
#     independent of the still-unwritten code: an extraction denominator over SKILL.md's
#     ALREADY-PRESENT guard prose, and four literals byte-preserved in text nothing has edited yet.
#     Recorded here so a reader does not "fix" the test to force any of the five red.
#
# ADDED LATER, not part of the block above (rule 14 — the dated record above is a correct snapshot
# of 2026-09-05 and is not rewritten): CX28 and CX29 were added on 2026-09-06 as regression cover
# for two fixes that had landed in codex-reviewer.sh after this file was written and that nothing
# pinned — the `uncommitted` diff-scope arm's own git-exit guard, and the absolute-path
# normalisation of a finding's `file`. Both were measured GREEN against the code as it stands the
# day they were added; a RED in either is a regression in that code, never an unfinished task.
# Z1's floor and its frozen-identity-set sentence were re-derived by running this file, not
# computed (rule 10, rule 13).
#
# ALSO ADDED 2026-09-06, by the coverage-gap pass of that same RTF cycle and after the paragraph
# above was written (rule 14 — that paragraph is a correct snapshot of its moment and is not
# rewritten): CX30, CX31 and CX32. CX30 pins REVIEW mode's three diff-scope arms, which carried the
# same failing-git-call defect CX28 pins in audit mode and were fixed alongside it — and pins the
# opposite direction too, that a genuinely empty diff is still exit 0 "safe to merge" (rule 8).
# CX31 closes the gap CX06 left: the audit `base:`/`commit:` arms were only ever shown to be
# ACCEPTED, never driven through a genuinely failing git call. CX32 closes the gap CX08 left,
# covering the `[ ! -x ]` half of the enumerate-sources.sh guard where CX08 covers only `[ ! -r ]`.
# All three were measured GREEN against the code as it stands the day they were added, so a RED in
# any of them is a regression in codex-reviewer.sh, never an unfinished task. Z1's floor and its
# frozen-identity-set sentence were re-derived a second time by running this file, not computed
# (rule 10, rule 13): 30 -> 33.
#
# AND AGAIN 2026-09-06, after the paragraph above (rule 14 — that paragraph is a correct snapshot of
# its moment and is not rewritten): CX33, regression cover for the mktemp-failure guards just added
# to audit mode's diff-scope intersection block. Before that fix a failed `mktemp` fell through to an
# empty FILE_LIST and reported exit 0 with `[]`, indistinguishable from a genuinely empty diff; the
# assertion drives a real, selectively-failing `mktemp` end to end and requires exit 3 with the
# message naming WHICH temp file could not be created. Measured GREEN against the code as it stands
# the day it was added, so a RED in it is a regression in codex-reviewer.sh. Z1's floor and its
# frozen-identity-set sentence were re-derived a third time by running this file (rule 10, rule 13):
# 33 -> 34.
#
# AND AGAIN 2026-09-06, after the paragraph above (rule 14 — that paragraph too is a correct
# snapshot of its moment and is not rewritten): CX34, regression cover for the write and
# intersection guards added to the SAME diff-scope block one step past the mktemp pair CX33 pins.
# Before that fix a `printf` that failed after a successful `mktemp`, or a `grep -Fxf` that failed
# for an I/O reason, fell through to an empty FILE_LIST and reported exit 0 with `[]` —
# indistinguishable from a genuinely empty diff. The assertion drives all three failures end to end
# (an unwritable path handed back by a succeeding mktemp; a grep shim that exits 2 only on `-Fxf`)
# and requires exit 3 with the message naming WHICH step failed, plus the opposite direction: a
# repository with one modified file must still reach a real, non-empty intersection. Measured GREEN
# against the code as it stands the day it was added, so a RED in it is a regression in
# codex-reviewer.sh. Z1's floor and its frozen-identity-set sentence were re-derived a fourth time
# by running this file (rule 10, rule 13): 34 -> 35.
#
# TWENTY-FIVE `# plant:` declarations sit beside CX02, CX05, CX10, CX12, CX13, CX14, CX15, CX17,
# CX18, CX20, CX21, CX22, CX23, CX24, CX26, CX28, CX29, CX30, CX31, CX32, CX33 and CX34 (rule 2 — an
# assertion nobody planted pins nothing) — twenty-five against twenty-two ids because CX33 carries
# TWO, one per mktemp guard, and CX34 carries THREE, one per failure path (the two writes and the
# intersection), so no half of either rests on the other's evidence. The ones targeting Task 2's argument
# surface (CX02, CX05) and the SKILL.md prose
# Tasks 6-8 add (CX20-CX24, CX26) are grounded in literal text the plan or the source files already
# state verbatim. The ones targeting Task 3/4's not-yet-written `codex-reviewer.sh` internals (CX10,
# CX12, CX13, CX17, CX18) are best-effort projections of that code's expected shape, following the
# file's own existing style; Task 9's plant run is explicitly budgeted (~10 lines) to repair a
# needle that turns out BADPLANT once the real code lands — "fix the needle, never the assertion"
# (plant-check.sh's own rule). The last ten (CX28, CX29, CX30, CX31, CX32, CX33's two and CX34's
# three) are not projections at all: they were written against code already on disk, so their
# needles are quoted from it.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO_ROOT=$(cd "$STAGING/.." && pwd)
CR="$SCRIPTS/codex-reviewer.sh"
SKILL_MD="$STAGING/plugin/skills/deep-refactor/SKILL.md"
ENUM_SCRIPT="$SCRIPTS/../skills/deep-refactor/scripts/enumerate-sources.sh"
ADR187="$REPO_ROOT/docs/architecture/ADR-0187-codex-review-gate.md"
ADR193="$REPO_ROOT/docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md"
CHAIN_INDEX="$REPO_ROOT/docs/chain-decision-index.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$CR" ]; then
  bad "S0: codex-reviewer.sh not found at $CR — nothing else in this file can run"
  echo "----"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
if [ ! -f "$SKILL_MD" ]; then
  bad "S0: deep-refactor/SKILL.md not found at $SKILL_MD — nothing else in this file can run"
  echo "----"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "S0: codex-reviewer.sh and deep-refactor/SKILL.md both found"

CR_TEXT=$(cat "$CR" 2>/dev/null)
SKILL_TEXT=$(cat "$SKILL_MD" 2>/dev/null)

# =====================================================================================
# Helpers — flattened-clause matching (rule 3: a clause is the same clause whether it wraps).

flatten() {
  tr '\n\t\r' '   ' | sed -E 's/ +/ /g; s/^ //; s/ $//'
}

flat_count() {
  # $1 = haystack text  $2 = needle text. Prints the number of non-overlapping occurrences.
  _fc_needle=$(printf '%s' "$2" | flatten)
  if [ -z "$_fc_needle" ]; then printf '0'; return; fi
  _fc_hay=$(printf '%s' "$1" | flatten)
  printf '%s' "$_fc_hay" | grep -o -F "$_fc_needle" | wc -l | tr -d ' '
}

flat_has() {
  [ "$(flat_count "$1" "$2")" -ge 1 ]
}

# =====================================================================================
# Helpers — extraction from the two real source files (never hard-coded copies, ADR-0193 §D6/§A9).

extract_guard() {
  # $1 = anchor regex for the "### Mandatory guard N — ..." heading. Prints the quoted instruction
  # text on the first `> "..."` blockquote line found after it, empty if not found.
  awk -v h="$1" '
    $0 ~ h { infield=1; next }
    infield && /^> "/ {
      line = $0
      sub(/^> "/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$SKILL_MD"
}
GUARD1=$(extract_guard "^### Mandatory guard 1")
GUARD2=$(extract_guard "^### Mandatory guard 2")

extract_finding_schema_block() {
  awk '
    /^```json$/ { c++; if (c==1) { capturing=1; next } }
    capturing && /^```$/ { capturing=0; next }
    capturing { print }
  ' "$SKILL_MD"
}
FINDING_SCHEMA_BLOCK=$(extract_finding_schema_block)
FINDING_FIELDS=$(printf '%s\n' "$FINDING_SCHEMA_BLOCK" | grep -oE '"[A-Za-z_]+":' | sed -E 's/[":]//g')
FINDING_FIELD_COUNT=$(printf '%s\n' "$FINDING_FIELDS" | grep -c .)
FINDING_FIELDS_CSV=$(printf '%s\n' "$FINDING_FIELDS" | tr '\n' ',' | sed -E 's/,$//')

extract_all_schema_blocks() {
  # $1 = output dir (already created). Writes every `<<'SCHEMA_EOF' ... SCHEMA_EOF` block's body to
  # $1/block-<n> in file order. All-blocks, never ordinal-trusted (ADR-0193 §D7's own lesson,
  # applied here independently of Task 5's ordinal-to-all-blocks repair to the sibling harness).
  awk -v outdir="$1" '
    /<<.SCHEMA_EOF.$/ { n++; capturing=1; fn = outdir "/block-" n; next }
    capturing && /^SCHEMA_EOF$/ { capturing=0; close(fn); next }
    capturing { print > fn }
  ' "$CR"
}

find_audit_schema() {
  # $1 = dir extract_all_schema_blocks wrote into. Prints the content of whichever block declares
  # "risk_level" (the field unique to the audit schema, absent from review's and diagnose's) —
  # never the ordinal position, since Task 3 may insert it anywhere among the SCHEMA_EOF blocks.
  for _fas_f in "$1"/block-*; do
    [ -f "$_fas_f" ] || continue
    if grep -q '"risk_level"' "$_fas_f" 2>/dev/null; then
      cat "$_fas_f"
      return 0
    fi
  done
  return 1
}

# =====================================================================================
# Helpers — the stub `codex` on an isolated PATH inside a mktemp -d, and PATH-with-no-codex.

WORK=$(mktemp -d)
STUBROOT=$(mktemp -d)
CR_ERR_FILE=$(mktemp)
trap 'rm -rf "$WORK" "$STUBROOT"; rm -f "$CR_ERR_FILE"' EXIT

build_stub_codex() {
  # $1 = directory to hold the stub `codex`. `doctor --json` reports auth ok; `exec` writes
  # $STUB_PAYLOAD (if set and readable) to the file named after `-o`, and tees the prompt it
  # received to $STUB_PROMPT_LOG (if set) — never a live call, always this cooperative fake.
  mkdir -p "$1"
  cat > "$1/codex" <<'STUB_EOF'
#!/bin/bash
set -u
case "${1:-}" in
  doctor)
    echo '{"checks":{"auth.credentials":{"status":"ok"}}}'
    exit 0
    ;;
  exec)
    shift
    OUTFILE=""
    PROMPT=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o) OUTFILE="$2"; shift 2 ;;
        --output-schema) shift 2 ;;
        --sandbox) shift 2 ;;
        *) PROMPT="$1"; shift ;;
      esac
    done
    if [ -n "${STUB_PROMPT_LOG:-}" ]; then
      printf '%s' "$PROMPT" > "$STUB_PROMPT_LOG"
    fi
    if [ -n "${STUB_PAYLOAD:-}" ] && [ -f "${STUB_PAYLOAD:-}" ] && [ -n "$OUTFILE" ]; then
      cp "${STUB_PAYLOAD:-}" "$OUTFILE"
    fi
    exit 0
    ;;
  *)
    echo "stub codex: unrecognised subcommand '${1:-}'" >&2
    exit 1
    ;;
esac
STUB_EOF
  chmod +x "$1/codex"
}

strip_codex_from_path() {
  # Prints $PATH with every directory that contains an executable `codex` removed — deterministic
  # regardless of whether the host running this suite happens to have the real CLI installed
  # somewhere. This is what "a PATH with no codex at all" means below, never an assumption.
  _scfp_out=""
  _scfp_oldifs="$IFS"
  IFS=':'
  for _scfp_d in $PATH; do
    if [ -z "$_scfp_d" ] || [ ! -x "$_scfp_d/codex" ]; then
      if [ -z "$_scfp_out" ]; then _scfp_out="$_scfp_d"; else _scfp_out="$_scfp_out:$_scfp_d"; fi
    fi
  done
  IFS="$_scfp_oldifs"
  printf '%s' "$_scfp_out"
}

NOCODEX_PATH=$(strip_codex_from_path)
STUBDIR="$STUBROOT/bin"
build_stub_codex "$STUBDIR"
STUB_PATH="$STUBDIR:$NOCODEX_PATH"

cr() {
  # $1 = PATH value; remaining = codex-reviewer.sh args. Sets CR_RC and CR_ERR (stderr text). Never
  # touches stdout — every codex-reviewer.sh mode writes results to --out, per its own CHECKER
  # contract (exit code is the signal, not stdout).
  _cr_p="$1"; shift
  : > "$CR_ERR_FILE"
  PATH="$_cr_p" bash "$CR" "$@" >/dev/null 2>"$CR_ERR_FILE"
  CR_RC=$?
  CR_ERR=$(cat "$CR_ERR_FILE")
}

set_stub() {
  # $1 = payload file (or ""), $2 = prompt-log file (or ""). Exported so the stub subprocess sees
  # them; codex-reviewer.sh itself never reads either variable, so no leakage into real behaviour.
  export STUB_PAYLOAD="$1"
  export STUB_PROMPT_LOG="$2"
}

MINIMAL_PAYLOAD="$WORK/minimal-payload.json"
printf '{"findings": []}\n' > "$MINIMAL_PAYLOAD"

# =====================================================================================
# CX01-CX09 (R-01) — the audit mode's argument surface and availability cascade.

cr "$NOCODEX_PATH" --mode audit --dimension dead-code --out "$WORK/cx01.json"
if [ "$CR_RC" -eq 3 ]; then
  ok "CX01: --mode audit --dimension dead-code --out <f> with no codex on PATH exits 3 (DID-NOT-RUN), not 2 — the mode IS recognised"
else
  bad "CX01: expected exit 3 (DID-NOT-RUN) with no codex on PATH, got exit $CR_RC — $CR_ERR"
fi

cr "$NOCODEX_PATH" --mode audit --dimension notadimension --out "$WORK/cx02.json"
CX02_NAMES_ALL=1
for _cx02_d in dead-code perf structure security; do
  printf '%s' "$CR_ERR" | grep -q -F "$_cx02_d" || CX02_NAMES_ALL=0
done
if [ "$CR_RC" -eq 2 ] && [ "$CX02_NAMES_ALL" -eq 1 ]; then
  ok "CX02: --dimension notadimension exits 2 and stderr names all four valid dimension values"
else
  bad "CX02: --dimension notadimension — rc=$CR_RC (want 2), names-all-four=$CX02_NAMES_ALL — $CR_ERR"
fi
# plant: CX02 | plugin/scripts/codex-reviewer.sh | dead-code|perf|structure|security) ;; | *) ;;

cr "$NOCODEX_PATH" --mode audit --out "$WORK/cx03.json"
[ "$CR_RC" -eq 2 ] \
  && ok "CX03: --mode audit with --dimension omitted exits 2" \
  || bad "CX03: --mode audit, --dimension omitted — expected exit 2, got $CR_RC — $CR_ERR"

cr "$NOCODEX_PATH" --mode audit --dimension perf
[ "$CR_RC" -eq 2 ] \
  && ok "CX04: --mode audit --dimension perf with --out omitted exits 2 (shared requirement, not bypassed)" \
  || bad "CX04: --mode audit --dimension perf, --out omitted — expected exit 2, got $CR_RC — $CR_ERR"

cr "$NOCODEX_PATH" --mode audit --dimension structure --diff-scope sometimes --out "$WORK/cx05.json"
[ "$CR_RC" -eq 2 ] \
  && ok "CX05: --diff-scope sometimes in audit mode exits 2" \
  || bad "CX05: --diff-scope sometimes in audit mode — expected exit 2, got $CR_RC — $CR_ERR"
# plant: CX05 | plugin/scripts/codex-reviewer.sh | uncommitted|base:*|commit:*) ;; | *) ;;

CX06_RAN=0
CX06_ALL_ACCEPTED=1
for _cx06_v in uncommitted base:HEAD commit:HEAD; do
  CX06_RAN=$((CX06_RAN + 1))
  set_stub "$MINIMAL_PAYLOAD" ""
  cr "$STUB_PATH" --mode audit --dimension structure --diff-scope "$_cx06_v" --out "$WORK/cx06-$CX06_RAN.json"
  [ "$CR_RC" -eq 2 ] && CX06_ALL_ACCEPTED=0
done
if [ "$CX06_RAN" -eq 3 ] && [ "$CX06_ALL_ACCEPTED" -eq 1 ]; then
  ok "CX06: all three locked --diff-scope values accepted in audit mode (loop ran $CX06_RAN times, none rejected)"
else
  bad "CX06: loop ran $CX06_RAN time(s) (need 3), all-accepted=$CX06_ALL_ACCEPTED"
fi

cr "$NOCODEX_PATH" --mode review --diff-scope bogus --out "$WORK/cx07a.json"
CX07_A=$([ "$CR_RC" -eq 2 ] && echo 1 || echo 0)
cr "$NOCODEX_PATH" --mode diagnose --out "$WORK/cx07b.json"
CX07_B=$([ "$CR_RC" -eq 2 ] && echo 1 || echo 0)
cr "$NOCODEX_PATH" --mode notamode --out "$WORK/cx07c.json"
CX07_C_RC=$([ "$CR_RC" -eq 2 ] && echo 1 || echo 0)
CX07_C_NAMES=1
printf '%s' "$CR_ERR" | grep -q "review" || CX07_C_NAMES=0
printf '%s' "$CR_ERR" | grep -q "diagnose" || CX07_C_NAMES=0
if [ "$CX07_A" -eq 1 ] && [ "$CX07_B" -eq 1 ] && [ "$CX07_C_RC" -eq 1 ] && [ "$CX07_C_NAMES" -eq 1 ]; then
  ok "CX07: the two existing modes are unchanged, both directions — review/diagnose validation intact, unknown-mode message still names both"
else
  bad "CX07: existing-mode regression — review-bogus-diffscope-exit2=$CX07_A diagnose-no-finding-exit2=$CX07_B notamode-exit2=$CX07_C_RC notamode-names-both=$CX07_C_NAMES"
fi

CX08_TMP=$(mktemp -d)
cp -R "$STAGING/plugin" "$CX08_TMP/plugin"
CX08_ENUM="$CX08_TMP/plugin/skills/deep-refactor/scripts/enumerate-sources.sh"
[ -f "$CX08_ENUM" ] && mv "$CX08_ENUM" "$CX08_ENUM.moved-aside"
# `cr()` always targets $CR (the real script); this run needs the COPY with the helper moved aside,
# so invoke it directly rather than reusing that helper.
CX08_ERR_FILE=$(mktemp)
PATH="$STUB_PATH" bash "$CX08_TMP/plugin/scripts/codex-reviewer.sh" --mode audit --dimension dead-code --out "$CX08_TMP/out.json" >/dev/null 2>"$CX08_ERR_FILE"
CX08_RC=$?
CX08_ERR=$(cat "$CX08_ERR_FILE")
rm -f "$CX08_ERR_FILE"
if [ "$CX08_RC" -eq 3 ] && printf '%s' "$CX08_ERR" | grep -qi 'enumerate-sources.sh'; then
  ok "CX08: enumerate-sources.sh made unreachable -> audit mode exits 3 naming the helper, no silent fallback onto a duplicated exclusion list"
else
  bad "CX08: expected exit 3 naming enumerate-sources.sh with the helper moved aside — rc=$CX08_RC err=$CX08_ERR"
fi
rm -rf "$CX08_TMP"

CX09_EXISTS=0
[ -r "$ENUM_SCRIPT" ] && CX09_EXISTS=1
CX09_STRING=0
grep -qF '../skills/deep-refactor/scripts/enumerate-sources.sh' "$CR" 2>/dev/null && CX09_STRING=1
if [ "$CX09_EXISTS" -eq 1 ] && [ "$CX09_STRING" -eq 1 ]; then
  ok "CX09: enumerate-sources.sh, resolved from codex-reviewer.sh's own dir, exists in the staging tree; the relative-path literal is present in codex-reviewer.sh"
else
  bad "CX09: resolved-path-exists=$CX09_EXISTS (at $ENUM_SCRIPT), literal-string-in-codex-reviewer.sh=$CX09_STRING"
fi

# =====================================================================================
# CX10-CX13 (R-02) — the FINDINGS_SCHEMA-shaped JSON output, end to end against the stub.

CX10_DIR=$(mktemp -d)
extract_all_schema_blocks "$CX10_DIR"
AUDIT_SCHEMA=$(find_audit_schema "$CX10_DIR")
if [ "$FINDING_FIELD_COUNT" -lt 7 ]; then
  bad "CX10: denominator broken — only $FINDING_FIELD_COUNT field name(s) extracted from SKILL.md's finding-schema fence (need >= 7, rule 7)"
elif [ -z "$AUDIT_SCHEMA" ]; then
  bad "CX10: no audit --output-schema SCHEMA_EOF block found in codex-reviewer.sh (searched every block for one declaring risk_level)"
else
  CX10_VERDICT=$(SCHEMA_JSON="$AUDIT_SCHEMA" REQ_FIELDS="$FINDING_FIELDS_CSV" python3 -c '
import json, os, sys
try:
    doc = json.loads(os.environ["SCHEMA_JSON"])
except Exception as e:
    print("PARSE-ERROR: %s" % e); sys.exit(0)
req_fields = [f for f in os.environ["REQ_FIELDS"].split(",") if f]
try:
    item_required = set(doc["properties"]["findings"]["items"]["required"])
except Exception as e:
    print("SHAPE-ERROR: %s" % e); sys.exit(0)
missing = [f for f in req_fields if f not in item_required]
print(("MISSING: " + ",".join(missing)) if missing else "OK")
')
  case "$CX10_VERDICT" in
    OK) ok "CX10: audit schema parses as JSON and its findings-item required[] is a superset of SKILL.md's finding-schema field set" ;;
    *) bad "CX10: $CX10_VERDICT" ;;
  esac
fi
rm -rf "$CX10_DIR"
# plant: CX10 | plugin/scripts/codex-reviewer.sh | "file", "line", "description", "fix_type", "suggested_fix"] | "file", "line", "description", "fix_type"]

CX11_PAYLOAD="$WORK/cx11-payload.json"
cat > "$CX11_PAYLOAD" <<'JSON'
{"findings": [
  {"id":"STUB-JUNK","dimension":"structure","severity":"P2","risk_level":"low","file":"src/A.swift","line":10,"description":"d1","fix_type":"coder","suggested_fix":"s1"},
  {"id":"STUB-JUNK2","dimension":"structure","severity":"P1","risk_level":"high","file":"src/B.swift","line":null,"description":"d2","fix_type":"refactorer","suggested_fix":"s2"}
]}
JSON
CX11_OUT="$WORK/cx11-out.json"
set_stub "$CX11_PAYLOAD" "$WORK/cx11-prompt.txt"
cr "$STUB_PATH" --mode audit --dimension perf --out "$CX11_OUT"
if [ "$CR_RC" -eq 0 ] && [ -s "$CX11_OUT" ]; then
  CX11_VERDICT=$(OUTFILE="$CX11_OUT" python3 -c '
import json, os
path = os.environ["OUTFILE"]
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    print("PARSE-ERROR: %s" % e); raise SystemExit
if not isinstance(data, list):
    print("NOT-ARRAY"); raise SystemExit
need = ["id","dimension","severity","risk_level","file","line","description","fix_type","suggested_fix"]
bad_els = []
for i, el in enumerate(data):
    missing = [k for k in need if k not in el]
    if missing:
        bad_els.append("%d:%s" % (i, ",".join(missing)))
print(("MISSING(%d elements, %d bad): %s" % (len(data), len(bad_els), "; ".join(bad_els))) if bad_els else ("OK(%d elements)" % len(data)))
')
  case "$CX11_VERDICT" in
    OK*) ok "CX11: --out holds a valid top-level JSON array and every element carries all nine fields — $CX11_VERDICT" ;;
    *) bad "CX11: end-to-end audit output malformed — $CX11_VERDICT" ;;
  esac
else
  bad "CX11: end-to-end audit run did not succeed — rc=$CR_RC out-non-empty=$([ -s "$CX11_OUT" ] && echo yes || echo no) err=$CR_ERR"
fi

if [ -s "$CX11_OUT" ]; then
  CX12_VERDICT=$(OUTFILE="$CX11_OUT" python3 -c '
import json, os
data = json.load(open(os.environ["OUTFILE"]))
if not isinstance(data, list) or not data:
    print("EMPTY-OR-NOT-ARRAY"); raise SystemExit
bad = [i for i, el in enumerate(data) if el.get("dimension") != "perf"]
print("OK" if not bad else ("WRONG-DIMENSION-AT:%s" % bad))
')
else
  CX12_VERDICT="NO-OUTPUT (see CX11)"
fi
case "$CX12_VERDICT" in
  OK) ok "CX12: stub's dimension=structure is overridden — every output element carries the --dimension perf argument instead" ;;
  *) bad "CX12: dimension forcing did not apply — $CX12_VERDICT" ;;
esac
# plant: CX12 | plugin/scripts/codex-reviewer.sh | dimension = DIMENSION

if [ -s "$CX11_OUT" ]; then
  CX13_VERDICT=$(OUTFILE="$CX11_OUT" python3 -c '
import json, os, re
data = json.load(open(os.environ["OUTFILE"]))
bad_junk = [el.get("id") for el in data if isinstance(el.get("id"), str) and el["id"].startswith("STUB-JUNK")]
pat = re.compile(r"^perf-[^-]+-.{3}$")
bad_shape = [el.get("id") for el in data if not pat.match(el.get("id") or "")]
if bad_junk:
    print("STUB-ID-LEAKED:%s" % bad_junk)
elif bad_shape:
    print("BAD-SHAPE:%s" % bad_shape)
else:
    print("OK")
')
else
  CX13_VERDICT="NO-OUTPUT (see CX11)"
fi
case "$CX13_VERDICT" in
  OK) ok 'CX13: the stub'"'"'s id (STUB-JUNK*) never survives; every synthesised id matches ^<dimension>-[^-]+-.{3}$' ;;
  *) bad "CX13: id-synthesis check failed — $CX13_VERDICT" ;;
esac
# plant: CX13 | plugin/scripts/codex-reviewer.sh | 'id': fid,

# =====================================================================================
# CX14-CX17 (R-03) — the two mandatory guards, extracted from SKILL.md, embedded verbatim and
# dimension-correctly in codex-reviewer.sh's audit prompt.

CX14_COUNT=$(flat_count "$CR_TEXT" "$GUARD1")
if [ -n "$GUARD1" ] && [ "$CX14_COUNT" -ge 1 ]; then
  ok "CX14: Mandatory guard 1's string, extracted from SKILL.md, appears whitespace-flattened in codex-reviewer.sh"
else
  bad "CX14: guard 1 not found in codex-reviewer.sh — extracted-from-SKILL.md=$([ -n "$GUARD1" ] && echo yes || echo no), occurrences=$CX14_COUNT"
fi
# plant: CX14 | plugin/scripts/codex-reviewer.sh | reflection-reachable, protocol-witness symbols. | reflection-reachable, protocol-witness helpers.

CX15_COUNT=$(flat_count "$CR_TEXT" "$GUARD2")
if [ -n "$GUARD2" ] && [ "$CX15_COUNT" -ge 1 ]; then
  ok "CX15: Mandatory guard 2's string, extracted from SKILL.md, appears whitespace-flattened in codex-reviewer.sh"
else
  bad "CX15: guard 2 not found in codex-reviewer.sh — extracted-from-SKILL.md=$([ -n "$GUARD2" ] && echo yes || echo no), occurrences=$CX15_COUNT"
fi
# plant: CX15 | plugin/scripts/codex-reviewer.sh | Auto-fix only synchronous perf patterns. | Auto-fix only synchronous performance patterns.

CX16_GCOUNT=0
[ -n "$GUARD1" ] && CX16_GCOUNT=$((CX16_GCOUNT + 1))
[ -n "$GUARD2" ] && CX16_GCOUNT=$((CX16_GCOUNT + 1))
if [ "$CX16_GCOUNT" -eq 2 ] && [ "${#GUARD1}" -ge 80 ] && [ "${#GUARD2}" -ge 80 ]; then
  ok "CX16: exactly two guard strings extracted from SKILL.md, each >= 80 chars (len1=${#GUARD1}, len2=${#GUARD2})"
else
  bad "CX16: guard-extraction denominator broken — extracted=$CX16_GCOUNT (need 2), len1=${#GUARD1}, len2=${#GUARD2}"
fi

CX17_ALL_OK=1
CX17_DETAILS=""
if [ -z "$GUARD1" ] || [ -z "$GUARD2" ]; then
  CX17_ALL_OK=0
  CX17_DETAILS="guard extraction from SKILL.md failed, cannot check embedding"
else
  for _cx17_dim in dead-code perf structure security; do
    _cx17_plog="$WORK/cx17-prompt-$_cx17_dim.txt"
    _cx17_out="$WORK/cx17-out-$_cx17_dim.json"
    set_stub "$MINIMAL_PAYLOAD" "$_cx17_plog"
    cr "$STUB_PATH" --mode audit --dimension "$_cx17_dim" --out "$_cx17_out"
    _cx17_ptext=""
    [ -f "$_cx17_plog" ] && _cx17_ptext=$(cat "$_cx17_plog")
    _cx17_g1=0; _cx17_g2=0
    flat_has "$_cx17_ptext" "$GUARD1" && _cx17_g1=1
    flat_has "$_cx17_ptext" "$GUARD2" && _cx17_g2=1
    case "$_cx17_dim" in
      dead-code) [ "$_cx17_g1" -eq 1 ] && [ "$_cx17_g2" -eq 0 ] || { CX17_ALL_OK=0; CX17_DETAILS="$CX17_DETAILS dead-code(g1=$_cx17_g1,g2=$_cx17_g2)"; } ;;
      perf) [ "$_cx17_g2" -eq 1 ] && [ "$_cx17_g1" -eq 0 ] || { CX17_ALL_OK=0; CX17_DETAILS="$CX17_DETAILS perf(g1=$_cx17_g1,g2=$_cx17_g2)"; } ;;
      structure) [ "$_cx17_g1" -eq 0 ] && [ "$_cx17_g2" -eq 0 ] || { CX17_ALL_OK=0; CX17_DETAILS="$CX17_DETAILS structure(g1=$_cx17_g1,g2=$_cx17_g2)"; } ;;
      security) [ "$_cx17_g1" -eq 0 ] && [ "$_cx17_g2" -eq 0 ] || { CX17_ALL_OK=0; CX17_DETAILS="$CX17_DETAILS security(g1=$_cx17_g1,g2=$_cx17_g2)"; } ;;
    esac
  done
fi
if [ "$CX17_ALL_OK" -eq 1 ]; then
  ok "CX17: dimension-correct guard embedding holds in all four directions (dead-code=guard1-only, perf=guard2-only, structure/security=neither)"
else
  bad "CX17: guard embedding wrong for:$CX17_DETAILS"
fi
# plant: CX17 | plugin/scripts/codex-reviewer.sh | "$DIMENSION" = "perf" | "$DIMENSION" != ""

# =====================================================================================
# CX18-CX19 (R-04) — security forces fix_type: report-only; the forcing does not leak elsewhere.

CX18_PAYLOAD="$WORK/cx18-payload.json"
cat > "$CX18_PAYLOAD" <<'JSON'
{"findings": [
  {"id":"STUB-SEC","dimension":"security","severity":"P1","risk_level":"high","file":"src/Sec.swift","line":5,"description":"secret","fix_type":"coder","suggested_fix":"remove it"}
]}
JSON
CX18_OUT="$WORK/cx18-out.json"
set_stub "$CX18_PAYLOAD" "$WORK/cx18-prompt.txt"
cr "$STUB_PATH" --mode audit --dimension security --out "$CX18_OUT"
if [ -s "$CX18_OUT" ]; then
  CX18_VERDICT=$(OUTFILE="$CX18_OUT" python3 -c '
import json, os
data = json.load(open(os.environ["OUTFILE"]))
bad = [el.get("fix_type") for el in data if el.get("fix_type") != "report-only"]
print("OK" if not bad else ("NOT-FORCED:%s" % bad))
')
else
  CX18_VERDICT="NO-OUTPUT rc=$CR_RC err=$CR_ERR"
fi
case "$CX18_VERDICT" in
  OK) ok "CX18: --dimension security forces fix_type=report-only on every element, regardless of the stub's 'coder'" ;;
  *) bad "CX18: security fix_type forcing failed — $CX18_VERDICT" ;;
esac
# plant: CX18 | plugin/scripts/codex-reviewer.sh | if dimension == 'security':

CX19_OUT="$WORK/cx19-out.json"
set_stub "$CX18_PAYLOAD" "$WORK/cx19-prompt.txt"
cr "$STUB_PATH" --mode audit --dimension dead-code --out "$CX19_OUT"
if [ -s "$CX19_OUT" ]; then
  CX19_VERDICT=$(OUTFILE="$CX19_OUT" python3 -c '
import json, os
data = json.load(open(os.environ["OUTFILE"]))
bad = [el.get("fix_type") for el in data if el.get("fix_type") != "coder"]
print("OK" if not bad else ("OVER-FORCED:%s" % bad))
')
else
  CX19_VERDICT="NO-OUTPUT rc=$CR_RC err=$CR_ERR"
fi
case "$CX19_VERDICT" in
  OK) ok "CX19: the same stub payload through --dimension dead-code leaves fix_type=coder untouched — forcing is security-scoped, not global (rule 8)" ;;
  *) bad "CX19: fix_type forcing leaked outside security — $CX19_VERDICT" ;;
esac

# =====================================================================================
# CX20-CX24 (R-05, R-06, R-07, R-08, R-09, R-10, R-11) — deep-refactor/SKILL.md's dispatch model,
# Gate 0-CDX, and Gate 1 engine attribution.

DISPATCH_BLOCK=$(awk '
  /^### Dispatch model$/ { capturing=1; next }
  capturing && /^### / { exit }
  capturing { print }
' "$SKILL_MD")

CX20_CMD_COUNT=$(flat_count "$DISPATCH_BLOCK" "codex-reviewer.sh --mode audit --dimension")
CX20_IF_COUNT=$(flat_count "$DISPATCH_BLOCK" "USE_CODEX_AUDIT = true")
if [ "$CX20_CMD_COUNT" -eq 2 ] && [ "$CX20_IF_COUNT" -eq 2 ]; then
  ok "CX20: both dispatch branches carry an IF USE_CODEX_AUDIT = true half naming codex-reviewer.sh --mode audit --dimension — exactly two branches"
else
  bad "CX20: expected exactly 2 branches naming the audit CLI and the flag-true condition — cli-mentions=$CX20_CMD_COUNT flag-true-mentions=$CX20_IF_COUNT"
fi
# plant: CX20 | plugin/skills/deep-refactor/SKILL.md | Branch A — Workflow dispatch (default): IF USE_CODEX_AUDIT = true | Branch A — Workflow dispatch (default):

CX21_N1=$(flat_count "$SKILL_TEXT" 'model: "opus", effort: "high"')
CX21_N2=$(flat_count "$SKILL_TEXT" "inherit the session")
CX21_N3=$(flat_count "$SKILL_TEXT" "Dispatch the 4 reviewer agents sequentially using the")
CX21_N4=$(flat_count "$SKILL_TEXT" "dispatch-site: deep-refactor-reviewers")
if [ "$CX21_N1" -eq 1 ] && [ "$CX21_N2" -eq 1 ] && [ "$CX21_N3" -eq 1 ] && [ "$CX21_N4" -eq 1 ]; then
  ok "CX21: byte-preservation of the Claude-only ELSE — all four frozen literals present exactly once each"
else
  bad "CX21: a frozen literal is missing or duplicated in the Claude-only ELSE — opus/effort=$CX21_N1 inherit-session=$CX21_N2 dispatch-4-sequential=$CX21_N3 dispatch-site-marker=$CX21_N4 (each must be 1)"
fi
# plant: CX21 | plugin/skills/deep-refactor/SKILL.md | Dispatch the 4 reviewer agents sequentially using the | Dispatch the four reviewer agents sequentially using the

CX22_HEADING_COUNT=$(flat_count "$SKILL_TEXT" "### HITL Gate 0-CDX")
CX22_POS_OK=0
if [ "$CX22_HEADING_COUNT" -ge 1 ]; then
  _cx22_gate0=$(grep -n '^### HITL Gate 0 — Approval to start$' "$SKILL_MD" | head -1 | cut -d: -f1)
  _cx22_cdx=$(grep -n '^### HITL Gate 0-CDX' "$SKILL_MD" | head -1 | cut -d: -f1)
  _cx22_phase1=$(grep -n '^## Phase 1' "$SKILL_MD" | head -1 | cut -d: -f1)
  if [ -n "$_cx22_gate0" ] && [ -n "$_cx22_cdx" ] && [ -n "$_cx22_phase1" ] \
     && [ "$_cx22_cdx" -gt "$_cx22_gate0" ] && [ "$_cx22_cdx" -lt "$_cx22_phase1" ]; then
    CX22_POS_OK=1
  fi
fi
CX22_SHAPE_OK=0
if [ "$CX22_HEADING_COUNT" -ge 1 ]; then
  CDX_BLOCK=$(awk '
    /^### HITL Gate 0-CDX/ { c=1; next }
    c && /^### / { exit }
    c && /^## / { exit }
    c { print }
  ' "$SKILL_MD")
  if flat_has "$CDX_BLOCK" "AskUserQuestion" && flat_has "$CDX_BLOCK" "No — Claude only" && flat_has "$CDX_BLOCK" "(Recommended)"; then
    _cx22_first_opt=$(printf '%s\n' "$CDX_BLOCK" | grep -m1 -E '^[[:space:]]*-[[:space:]]*"')
    case "$_cx22_first_opt" in
      *"No — Claude only"*"(Recommended)"*) CX22_SHAPE_OK=1 ;;
    esac
  fi
fi
if [ "$CX22_HEADING_COUNT" -ge 1 ] && [ "$CX22_POS_OK" -eq 1 ] && [ "$CX22_SHAPE_OK" -eq 1 ]; then
  ok "CX22: Gate 0-CDX exists between Gate 0 and Phase 1, is AskUserQuestion-shaped, and lists 'No — Claude only' first with (Recommended)"
else
  bad "CX22: Gate 0-CDX check failed — heading-count=$CX22_HEADING_COUNT position-ok=$CX22_POS_OK shape-ok=$CX22_SHAPE_OK"
fi
# plant: CX22 | plugin/skills/deep-refactor/SKILL.md | ### HITL Gate 0-CDX — Audit engine (Codex or Claude)

CX23_NOQ=$(flat_count "$SKILL_TEXT" "no question is asked")
CX23_MFS=$(flat_count "$SKILL_TEXT" "manifest-field-state.sh")
CX23_NOMANIFEST=$(flat_count "$SKILL_TEXT" "with no manifest")
if [ "$CX23_NOQ" -ge 1 ] && [ "$CX23_MFS" -ge 1 ] && [ "$CX23_NOMANIFEST" -ge 1 ]; then
  ok "CX23: the unattended path is stated — no-question-under-autopilot, manifest-field-state.sh read for the inherited value, and a no-manifest-resolves-Claude-only clause"
else
  bad "CX23: unattended path under-documented — no-question-clause=$CX23_NOQ manifest-field-state.sh-mention=$CX23_MFS no-manifest-clause=$CX23_NOMANIFEST (each must be >= 1)"
fi
# plant: CX23 | plugin/skills/deep-refactor/SKILL.md | with no manifest

CX24_MARKER=$(flat_count "$SKILL_TEXT" "Audit engine per dimension:")
CX24_COND=$(flat_count "$SKILL_TEXT" "USE_CODEX_AUDIT was true for this run")
if [ "$CX24_MARKER" -ge 1 ] && [ "$CX24_COND" -ge 1 ]; then
  ok "CX24: Gate 1 gains a per-dimension engine-attribution block, conditional on USE_CODEX_AUDIT having been true for the run"
else
  bad "CX24: Gate 1 engine-attribution block not found — marker=$CX24_MARKER conditional-clause=$CX24_COND"
fi
# plant: CX24 | plugin/skills/deep-refactor/SKILL.md | Audit engine per dimension:

# =====================================================================================
# CX25-CX27 (R-11, plus the waived plan-side documentation id SPEC.md marks no-test) — no
# collateral drift; the ADR and its index entry.

CX25_ROWS=0
for _cx25_d in dead-code perf structure security; do
  _cx25_needle='| `'"$_cx25_d"'` | reviewer |'
  grep -qF "$_cx25_needle" "$SKILL_MD" && CX25_ROWS=$((CX25_ROWS + 1))
done
if [ "$CX25_ROWS" -eq 4 ] && [ "$FINDING_FIELD_COUNT" -eq 9 ]; then
  ok "CX25: no collateral drift — all four dimension table rows present, finding-schema fence still declares nine fields"
else
  bad "CX25: collateral drift detected — dimension-table-rows=$CX25_ROWS/4, finding-schema-field-count=$FINDING_FIELD_COUNT/9"
fi

ADR187_TEXT=$(cat "$ADR187" 2>/dev/null)
CX26_NEEDLE='This pass does not extend Codex substitution to `coder`/`tester` dispatch, to Gate 5.06 / `security-audit` / `deep-refactor`, or to `--autopilot` runs — all explicitly deferred, not solved.'
if flat_has "$ADR187_TEXT" "$CX26_NEEDLE"; then
  ok "CX26: ADR-0187's deferral sentence survives verbatim (whitespace-flattened) — the historical record is not corrected in place (rule 14)"
else
  bad "CX26: ADR-0187's deferral sentence has changed or is missing — rule 14 violation, or ADR-0187 was edited in place"
fi
# plant: CX26 | ../docs/architecture/ADR-0187-codex-review-gate.md | This pass does not extend Codex substitution to `coder`/`tester` dispatch, to Gate 5.06 / `security-audit` / `deep-refactor`, or to `--autopilot` runs — all explicitly deferred, not solved. | This pass does not extend Codex substitution to `coder`/`tester` dispatch, to Gate 5.06 / `security-audit` / `deep-refactor`, or to `--autopilot` runs — all already solved.

CX27_ADR_OK=0
[ -f "$ADR193" ] && grep -q "ADR-0187" "$ADR193" && CX27_ADR_OK=1
CX27_INDEX_OK=0
if [ -f "$CHAIN_INDEX" ]; then
  _cx27_line=$(grep -n "ADR-0193" "$CHAIN_INDEX" | head -1)
  if [ -n "$_cx27_line" ] && printf '%s' "$_cx27_line" | grep -q "ADR-0187"; then
    CX27_INDEX_OK=1
  fi
fi
if [ "$CX27_ADR_OK" -eq 1 ] && [ "$CX27_INDEX_OK" -eq 1 ]; then
  ok "CX27: ADR-0193 exists and names ADR-0187; docs/chain-decision-index.md carries an ADR-0193 entry that also names ADR-0187"
else
  bad "CX27: ADR-half=$CX27_ADR_OK index-half=$CX27_INDEX_OK — the index half is expected RED until Task 10 lands"
fi

# =====================================================================================
# CX28-CX29 (R-01, R-02) — regression coverage for two behaviours in codex-reviewer.sh that
# landed AFTER the CX01-CX27 set above was written and that nothing here pinned: the
# `uncommitted` diff-scope arm's own git-exit guard, and the absolute-path normalisation of a
# finding's `file` field. Both are behavioural end-to-end checks driven by the same stub `codex`
# every other CX block uses — never a live call.

# CX28 (R-01) — an UNBORN repository (`git init`, no commits) is the measured case where
# `git rev-parse --is-inside-work-tree` succeeds and `git diff HEAD` still exits 128, so the
# earlier "not a git repository" guard does not catch it. The `uncommitted` arm must report
# DID-NOT-RUN (exit 3, rule 4), never a silent empty CHANGED_FILES that intersects to nothing and
# reads as a clean audit of a scope that was never evaluated (rule 7 — the same failure one level
# down, a derived population collapsing to zero and looking like a result).
#
# codex-reviewer.sh issues bare `git ...`, never `git -C`, so the repository it audits is whatever
# its CWD is and this run has to be made from inside the scratch repo. `cr()` never changes
# directory, so it cannot be reused; the `cd` is confined to a subshell instead, leaving the
# suite's own CWD untouched for every assertion after this one (CX29 below depends on that).
CX28_REPO="$WORK/cx28-unborn"
mkdir -p "$CX28_REPO"
git init -q "$CX28_REPO" >/dev/null 2>&1
# Denominator guard (rule 7): assert the fixture really is unborn — a git that quietly created a
# commit, or no git at all, would make the assertion below pass or fail for the wrong reason.
CX28_UNBORN=0
if git -C "$CX28_REPO" rev-parse --git-dir >/dev/null 2>&1 \
   && ! git -C "$CX28_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
  CX28_UNBORN=1
fi
CX28_OUT="$WORK/cx28-out.json"
CX28_ERR_FILE=$(mktemp)
set_stub "$MINIMAL_PAYLOAD" ""
( cd "$CX28_REPO" && PATH="$STUB_PATH" bash "$CR" --mode audit --dimension structure --diff-scope uncommitted --out "$CX28_OUT" ) >/dev/null 2>"$CX28_ERR_FILE"
CX28_RC=$?
CX28_ERR=$(cat "$CX28_ERR_FILE")
rm -f "$CX28_ERR_FILE"
CX28_MSG=0
if printf '%s' "$CX28_ERR" | grep -q -F 'DID-NOT-RUN' \
   && printf '%s' "$CX28_ERR" | grep -q -F "could not resolve diff-scope 'uncommitted'"; then
  CX28_MSG=1
fi
CX28_NO_ARTIFACT=0
[ ! -s "$CX28_OUT" ] && CX28_NO_ARTIFACT=1
if [ "$CX28_UNBORN" -eq 1 ] && [ "$CX28_RC" -eq 3 ] && [ "$CX28_MSG" -eq 1 ] && [ "$CX28_NO_ARTIFACT" -eq 1 ]; then
  ok "CX28: --diff-scope uncommitted in an unborn repo exits 3 (DID-NOT-RUN) naming the unresolvable scope, and no --out artifact is written"
else
  bad "CX28: unborn-repo uncommitted scope — fixture-unborn=$CX28_UNBORN rc=$CX28_RC (want 3) message-ok=$CX28_MSG out-absent-or-empty=$CX28_NO_ARTIFACT — $CX28_ERR"
fi
# plant: CX28 | plugin/scripts/codex-reviewer.sh | CHANGED_FILES=$(git diff HEAD --name-only 2>/dev/null) _git_rc=$? | CHANGED_FILES=$(git diff HEAD --name-only 2>/dev/null)\n        _git_rc=0

# CX29 (R-02) — deep-refactor/SKILL.md's finding schema declares `"file": "<absolute path>"`, and
# Gate 1 dedupes the Codex-sourced findings against the Claude-sourced ones on file + line +
# description: a repo-relative value emitted here would never match its Claude-side twin, and the
# duplicate would read as two independent findings. Both directions are pinned in one assertion
# (rule 8): a relative path IS joined onto the repository root, and an already-absolute one is NOT
# prefixed a second time — the natural defect here is string concatenation without the isabs test,
# which breaks both at once.
#
# Same end-to-end shape as CX11 and the same context: $WORK for the payload and the artifact,
# $STUB_PATH for the fake `codex`, `cr()` — whose CWD is the suite's own, i.e. this repository —
# for the invocation. The root asserted against is derived from that same CWD by the same command
# codex-reviewer.sh itself uses, so the two sides answer one question from one place (rule 6),
# rather than hard-coding a checkout path this suite would then only pass in.
CX29_PAYLOAD="$WORK/cx29-payload.json"
cat > "$CX29_PAYLOAD" <<'JSON'
{"findings": [
  {"id":"STUB-JUNK-REL","dimension":"perf","severity":"P2","risk_level":"low","file":"src/A.swift","line":10,"description":"cx29-relative","fix_type":"coder","suggested_fix":"s1"},
  {"id":"STUB-JUNK-ABS","dimension":"perf","severity":"P1","risk_level":"high","file":"/already/absolute/src/B.swift","line":3,"description":"cx29-already-absolute","fix_type":"coder","suggested_fix":"s2"}
]}
JSON
CX29_OUT="$WORK/cx29-out.json"
CX29_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
set_stub "$CX29_PAYLOAD" ""
cr "$STUB_PATH" --mode audit --dimension structure --out "$CX29_OUT"
if [ -z "$CX29_TOPLEVEL" ]; then
  CX29_VERDICT="DID-NOT-RUN: this suite's CWD is not inside a git checkout, so the expected root cannot be derived"
elif [ "$CR_RC" -ne 0 ] || [ ! -s "$CX29_OUT" ]; then
  CX29_VERDICT="NO-OUTPUT rc=$CR_RC err=$CR_ERR"
else
  CX29_VERDICT=$(OUTFILE="$CX29_OUT" TOPLEVEL="$CX29_TOPLEVEL" python3 -c '
import json, os
data = json.load(open(os.environ["OUTFILE"]))
top = os.environ["TOPLEVEL"]
if not isinstance(data, list) or len(data) != 2:
    print("EXPECTED-2-ELEMENTS-GOT:%r" % (len(data) if isinstance(data, list) else type(data).__name__))
    raise SystemExit
# Keyed on description, never on array position: the ids are synthesised by the wrapper, and
# element order is not a claim this assertion is making.
by_desc = dict((el.get("description"), el.get("file")) for el in data)
rel_out = by_desc.get("cx29-relative")
abs_out = by_desc.get("cx29-already-absolute")
want_rel = os.path.join(top, "src/A.swift")
problems = []
if not isinstance(rel_out, str) or not rel_out.startswith("/"):
    problems.append("relative-input-not-absolutised:%r" % (rel_out,))
elif not rel_out.endswith("/src/A.swift"):
    problems.append("relative-suffix-lost:%r" % (rel_out,))
elif rel_out != want_rel:
    problems.append("wrong-root:%r want %r" % (rel_out, want_rel))
if abs_out != "/already/absolute/src/B.swift":
    problems.append("already-absolute-double-prefixed-or-altered:%r" % (abs_out,))
print("OK" if not problems else "; ".join(problems))
')
fi
case "$CX29_VERDICT" in
  OK) ok "CX29: a repo-relative finding 'file' is emitted absolute, joined onto the root git reports for this working directory; an already-absolute one passes through unprefixed" ;;
  *) bad "CX29: audit 'file' normalisation wrong — $CX29_VERDICT" ;;
esac
# plant: CX29 | plugin/scripts/codex-reviewer.sh | if file_val and not os.path.isabs(file_val): file_out = os.path.join(REPO_ROOT, file_val) | if file_val:\n        file_out = REPO_ROOT + file_val

# =====================================================================================
# CX30-CX32 (R-01) — three further regression assertions, added 2026-09-06 by the coverage-gap pass
# of the same RTF cycle that added CX28/CX29. Each drives a REAL git or filesystem failure end to
# end against the stub `codex`; none is a structural grep on codex-reviewer.sh's own source.

# CX30 (R-01) — REVIEW mode's three diff-scope arms. CX28 pins the AUDIT `uncommitted` arm; review
# mode carried the identical defect and was fixed in the same cycle: a failing git call left
# DIFF_CONTENT empty, indistinguishable from a genuinely empty diff, and fell into the "nothing to
# review, safe to merge" branch with exit 0 — a scope that was never evaluated reported as a clean
# review (rule 4, and rule 7 one level down).
#
# BOTH DIRECTIONS IN ONE ASSERTION (rule 8), because the cheap way to satisfy the new failure path
# is to make every empty diff exit 3, which would break the "no detectable changes" contract this
# script has documented in its own header since v1.0. So: three unresolvable scopes must be exit 3
# naming the scope, AND a genuinely empty diff in a healthy repository must still be exit 0 with the
# "safe to merge" report.
#
# TWO FIXTURES, because "the git call fails" has two different causes and one repo cannot exhibit
# both: an UNBORN repository (`git init`, no commits — the measured case where
# `git rev-parse --is-inside-work-tree` succeeds and `git diff HEAD` exits 128) for `uncommitted`,
# and a HEALTHY, committed, CLEAN repository for `base:<ref that does not exist>` and
# `commit:<sha that does not exist>`, so those two arms fail for the reason the assertion names
# rather than for the unborn state. That same healthy fixture is the empty-diff positive case.
# codex-reviewer.sh issues bare `git ...`, never `git -C`, so each run happens inside its fixture;
# `cr()` never changes directory, so the `cd` is confined to a subshell exactly as CX28 does it.
CX30_UNBORN_REPO="$WORK/cx30-unborn"
mkdir -p "$CX30_UNBORN_REPO"
git init -q "$CX30_UNBORN_REPO" >/dev/null 2>&1
CX30_HEALTHY_REPO="$WORK/cx30-healthy"
mkdir -p "$CX30_HEALTHY_REPO"
git init -q "$CX30_HEALTHY_REPO" >/dev/null 2>&1
printf 'let cx30 = 1\n' > "$CX30_HEALTHY_REPO/A.swift"
git -C "$CX30_HEALTHY_REPO" add A.swift >/dev/null 2>&1
git -C "$CX30_HEALTHY_REPO" -c user.email=cx30@example.invalid -c user.name=cx30 \
    -c commit.gpgsign=false commit -q -m "cx30 fixture" >/dev/null 2>&1
# Denominator guard (rule 7): both fixtures must really be what the assertion claims. A git that
# quietly created a commit in the "unborn" one, or a dirty/HEAD-less "healthy" one, would make the
# checks below pass or fail for a reason unrelated to the mechanism under test.
CX30_FIXTURES_OK=1
git -C "$CX30_UNBORN_REPO" rev-parse --git-dir >/dev/null 2>&1 || CX30_FIXTURES_OK=0
if git -C "$CX30_UNBORN_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then CX30_FIXTURES_OK=0; fi
git -C "$CX30_HEALTHY_REPO" rev-parse --verify HEAD >/dev/null 2>&1 || CX30_FIXTURES_OK=0
if [ -n "$(git -C "$CX30_HEALTHY_REPO" status --porcelain 2>/dev/null)" ]; then CX30_FIXTURES_OK=0; fi

CX30_RAN=0
CX30_BAD=""
for _cx30_scope in uncommitted base:cx30-no-such-ref commit:0000000000000000000000000000000000000000; do
  case "$_cx30_scope" in
    uncommitted) _cx30_repo="$CX30_UNBORN_REPO" ;;
    *) _cx30_repo="$CX30_HEALTHY_REPO" ;;
  esac
  CX30_RAN=$((CX30_RAN + 1))
  _cx30_out="$WORK/cx30-$CX30_RAN.json"
  _cx30_errf="$WORK/cx30-$CX30_RAN.err"
  set_stub "$MINIMAL_PAYLOAD" ""
  ( cd "$_cx30_repo" && PATH="$STUB_PATH" bash "$CR" --mode review --diff-scope "$_cx30_scope" --out "$_cx30_out" ) >/dev/null 2>"$_cx30_errf"
  _cx30_rc=$?
  _cx30_err=$(cat "$_cx30_errf")
  _cx30_why=""
  [ "$_cx30_rc" -eq 3 ] || _cx30_why="$_cx30_why rc=$_cx30_rc(want-3)"
  printf '%s' "$_cx30_err" | grep -q -F 'DID-NOT-RUN' || _cx30_why="$_cx30_why no-DID-NOT-RUN"
  printf '%s' "$_cx30_err" | grep -q -F "could not resolve diff-scope '$_cx30_scope'" || _cx30_why="$_cx30_why scope-not-named"
  [ ! -s "$_cx30_out" ] || _cx30_why="$_cx30_why artifact-written"
  if [ -n "$_cx30_why" ]; then
    CX30_BAD="$CX30_BAD [$_cx30_scope:$_cx30_why ]"
  fi
done

CX30_CLEAN_OUT="$WORK/cx30-clean.json"
CX30_CLEAN_ERRF="$WORK/cx30-clean.err"
set_stub "$MINIMAL_PAYLOAD" ""
( cd "$CX30_HEALTHY_REPO" && PATH="$STUB_PATH" bash "$CR" --mode review --diff-scope uncommitted --out "$CX30_CLEAN_OUT" ) >/dev/null 2>"$CX30_CLEAN_ERRF"
CX30_CLEAN_RC=$?
CX30_CLEAN_SAFE=0
if [ -s "$CX30_CLEAN_OUT" ] && grep -q -F 'safe to merge' "$CX30_CLEAN_OUT"; then CX30_CLEAN_SAFE=1; fi

if [ "$CX30_FIXTURES_OK" -eq 1 ] && [ "$CX30_RAN" -eq 3 ] && [ -z "$CX30_BAD" ] \
   && [ "$CX30_CLEAN_RC" -eq 0 ] && [ "$CX30_CLEAN_SAFE" -eq 1 ]; then
  ok "CX30: review mode — each of the three diff-scope forms exits 3 (DID-NOT-RUN) naming the unresolvable scope when its git call fails (loop ran $CX30_RAN times), and a genuinely empty diff in a clean repo still exits 0 with the 'safe to merge' report"
else
  bad "CX30: review-mode diff-scope failure handling — fixtures-ok=$CX30_FIXTURES_OK loop-ran=$CX30_RAN (need 3) failing-arms:${CX30_BAD:-none} empty-diff-rc=$CX30_CLEAN_RC (want 0) empty-diff-says-safe-to-merge=$CX30_CLEAN_SAFE"
fi
# plant: CX30 | plugin/scripts/codex-reviewer.sh | DIFF_CONTENT=$(git diff HEAD 2>/dev/null) _git_rc=$? | DIFF_CONTENT=$(git diff HEAD 2>/dev/null)\n      _git_rc=0

# CX31 (R-01) — AUDIT mode's `base:` and `commit:` arms, driven by a git call that genuinely fails.
# CX06 above proves only that the three diff-scope forms are ACCEPTED (not rejected with exit 2) in
# audit mode, and CX28 drives a real failure through the `uncommitted` arm alone: the exit-3
# propagation in the other two arms was asserted by nothing, so a revert there would have been
# invisible. Same healthy fixture CX30 builds — a repository where HEAD resolves and the tree is
# clean, so the only thing wrong is the ref/sha named on the command line.
CX31_FIXTURE_OK=0
if git -C "$CX30_HEALTHY_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then CX31_FIXTURE_OK=1; fi
CX31_RAN=0
CX31_BAD=""
for _cx31_scope in base:cx31-no-such-ref commit:1111111111111111111111111111111111111111; do
  CX31_RAN=$((CX31_RAN + 1))
  _cx31_out="$WORK/cx31-$CX31_RAN.json"
  _cx31_errf="$WORK/cx31-$CX31_RAN.err"
  set_stub "$MINIMAL_PAYLOAD" ""
  ( cd "$CX30_HEALTHY_REPO" && PATH="$STUB_PATH" bash "$CR" --mode audit --dimension structure --diff-scope "$_cx31_scope" --out "$_cx31_out" ) >/dev/null 2>"$_cx31_errf"
  _cx31_rc=$?
  _cx31_err=$(cat "$_cx31_errf")
  _cx31_why=""
  [ "$_cx31_rc" -eq 3 ] || _cx31_why="$_cx31_why rc=$_cx31_rc(want-3)"
  printf '%s' "$_cx31_err" | grep -q -F 'DID-NOT-RUN' || _cx31_why="$_cx31_why no-DID-NOT-RUN"
  printf '%s' "$_cx31_err" | grep -q -F "could not resolve diff-scope '$_cx31_scope'" || _cx31_why="$_cx31_why scope-not-named"
  [ ! -s "$_cx31_out" ] || _cx31_why="$_cx31_why artifact-written"
  if [ -n "$_cx31_why" ]; then
    CX31_BAD="$CX31_BAD [$_cx31_scope:$_cx31_why ]"
  fi
done
if [ "$CX31_FIXTURE_OK" -eq 1 ] && [ "$CX31_RAN" -eq 2 ] && [ -z "$CX31_BAD" ]; then
  ok "CX31: audit mode — base:<unknown ref> and commit:<unknown sha> each exit 3 (DID-NOT-RUN) naming the unresolvable scope and write no --out artifact (loop ran $CX31_RAN times)"
else
  bad "CX31: audit-mode base:/commit: failure handling — fixture-ok=$CX31_FIXTURE_OK loop-ran=$CX31_RAN (need 2) failing-arms:${CX31_BAD:-none}"
fi
# plant: CX31 | plugin/scripts/codex-reviewer.sh | CHANGED_FILES=$(git diff "$_ref"...HEAD --name-only 2>/dev/null) _git_rc=$? | CHANGED_FILES=$(git diff "$_ref"...HEAD --name-only 2>/dev/null)\n        _git_rc=0

# CX32 (R-01) — the OTHER half of the enumerate-sources.sh guard. CX08 covers the `[ ! -r ]` half by
# moving the helper aside; the `[ ! -x ]` half — present, readable, execute bit gone — was covered by
# nothing. The two halves are not interchangeable: with the `-x` test removed the guard passes and
# the run reaches `"$ENUM" "$REPO_ROOT"`, which fails with 126 and is reported as
# "enumerate-sources.sh failed (exit $_enum_rc)". The EXIT CODE is 3 either way, so an assertion
# reading only the code would stay green with the mechanism deleted (rule 1 one level down); the
# message is what distinguishes them, and it is quoted from the source rather than paraphrased.
#
# Same scratch-copy shape as CX08 (`cr()` always targets the real $CR, so it cannot be reused) and
# for the same reason: the execute bit is cleared on a COPY, never on the tree this suite is run
# from, so an interrupted run cannot leave the real helper unusable.
CX32_TMP=$(mktemp -d)
cp -R "$STAGING/plugin" "$CX32_TMP/plugin"
CX32_ENUM="$CX32_TMP/plugin/skills/deep-refactor/scripts/enumerate-sources.sh"
CX32_FIXTURE=0
if [ -f "$CX32_ENUM" ]; then
  chmod -x "$CX32_ENUM"
  # Denominator guard (rule 7): readable AND non-executable is the whole point — a copy that came
  # out unreadable would re-test CX08's half and read as coverage of this one.
  if [ -r "$CX32_ENUM" ] && [ ! -x "$CX32_ENUM" ]; then CX32_FIXTURE=1; fi
fi
CX32_OUT="$CX32_TMP/out.json"
CX32_ERR_FILE=$(mktemp)
set_stub "$MINIMAL_PAYLOAD" ""
PATH="$STUB_PATH" bash "$CX32_TMP/plugin/scripts/codex-reviewer.sh" --mode audit --dimension dead-code --out "$CX32_OUT" >/dev/null 2>"$CX32_ERR_FILE"
CX32_RC=$?
CX32_ERR=$(cat "$CX32_ERR_FILE")
rm -f "$CX32_ERR_FILE"
CX32_MSG=0
if printf '%s' "$CX32_ERR" | grep -q -F 'DID-NOT-RUN' \
   && printf '%s' "$CX32_ERR" | grep -q -F 'not found or not executable'; then
  CX32_MSG=1
fi
CX32_NO_ARTIFACT=0
[ ! -s "$CX32_OUT" ] && CX32_NO_ARTIFACT=1
if [ "$CX32_FIXTURE" -eq 1 ] && [ "$CX32_RC" -eq 3 ] && [ "$CX32_MSG" -eq 1 ] && [ "$CX32_NO_ARTIFACT" -eq 1 ]; then
  ok "CX32: enumerate-sources.sh present and readable but not executable -> audit mode exits 3 (DID-NOT-RUN) with the 'not found or not executable' message, and no --out artifact is written"
else
  bad "CX32: non-executable enumerate-sources.sh — fixture-readable-and-nonexec=$CX32_FIXTURE rc=$CX32_RC (want 3) message-ok=$CX32_MSG out-absent-or-empty=$CX32_NO_ARTIFACT — $CX32_ERR"
fi
rm -rf "$CX32_TMP"
# plant: CX32 | plugin/scripts/codex-reviewer.sh | [ ! -x "$ENUM" ] | false

# CX33 (R-01) — the two `mktemp` calls that back audit mode's diff-scope INTERSECTION, neither of
# which captured its exit status until the fix this pins. A failed `mktemp` left the variable empty,
# the `printf` that follows wrote nowhere, and `grep -Fxf` — whose stderr is already discarded —
# yielded an empty FILE_LIST, which the empty-result branch reports as a clean audit: exit 0 with
# `[]` at --out. A broken intersection and a genuinely empty diff were indistinguishable from
# outside (rule 7), the same shape CX28 and CX31 pin one step earlier in the same block.
#
# THE FIXTURE, AND WHY A BROKEN TMPDIR IS NOT IT. audit mode runs enumerate-sources.sh BEFORE this
# block to derive the whole-tree list, and that helper calls `mktemp` twice itself — so anything
# breaking mktemp process-wide trips the pre-existing enumerate guard ("enumerate-sources.sh failed
# (exit N)") and never reaches the two calls under test. Measured with a logging shim rather than
# assumed (rule 13): the whole run makes exactly four `mktemp` calls, two from enumerate-sources.sh's
# own process and then the two here.
#
# So the shim fails SELECTIVELY, and it selects by CALLER, not by a global call ordinal: it reads its
# parent's command line (`ps -o args= -p $PPID`) and counts only the invocations whose parent is
# codex-reviewer.sh, failing on the Nth of those. A global "fail the 3rd mktemp" counter would
# silently start targeting a call inside enumerate-sources.sh the day that helper allocates a third
# temp file, and the assertion would then be pinning a guard it does not name.
#
# THE MESSAGE IS ASSERTED, NEVER JUST THE CODE. This script has many exit-3 paths, so `rc -eq 3`
# alone pins nothing (CX32's own lesson): each arm below requires the tail that names WHICH temp
# file could not be created — "whole-tree list" for the first call, "changed-paths list" for the
# second — which is also the only proof the shim isolated the call the arm claims it did.
#
# BOTH DIRECTIONS (rule 8), via the control run: the same fixture, the same shim, no injected
# failure, must still exit 0 with an empty findings array. Without it the cheap way to satisfy the
# new failure path would be to fail the whole intersection block. The control run doubles as the
# denominator guard (rule 7): it asserts the shim is really being invoked by codex-reviewer.sh and
# that exactly TWO calls originate there, so "call 1" and "call 2" below are the two guards named
# and not something further up the run.
CX33_SHIMDIR="$WORK/cx33-shim"
mkdir -p "$CX33_SHIMDIR"
CX33_REAL_MKTEMP=$(command -v mktemp 2>/dev/null)
cat > "$CX33_SHIMDIR/mktemp" <<'CX33_SHIM_EOF'
#!/bin/bash
# Counting mktemp shim for CX33 in codex-audit-mode.test.sh. Placed first on a PATH handed ONLY to
# the codex-reviewer.sh subprocess under test, never exported into this suite's own environment.
set -u
_cx33_parent=$(ps -o args= -p $PPID 2>/dev/null)
case "$_cx33_parent" in
  *codex-reviewer.sh*)
    _cx33_n=0
    if [ -f "${CX33_MK_COUNT:-/nonexistent}" ]; then _cx33_n=$(cat "$CX33_MK_COUNT"); fi
    _cx33_n=$((_cx33_n + 1))
    printf '%s\n' "$_cx33_n" > "$CX33_MK_COUNT"
    if [ "$_cx33_n" = "${CX33_MK_FAIL_NTH:-0}" ]; then
      printf '%s\n' "$_cx33_n" > "$CX33_MK_FIRED"
      printf 'cx33 mktemp shim: deliberate failure on codex-reviewer.sh call %s\n' "$_cx33_n" >&2
      exit 1
    fi
    # Not `exec`: the path handed back is logged, so the arm below can check that a temp file which
    # WAS created before the failing call is removed on the way out rather than leaked.
    _cx33_made=$("$CX33_MK_REAL" "$@")
    _cx33_rc=$?
    printf '%s\n' "$_cx33_made"
    printf '%s\n' "$_cx33_made" >> "$CX33_MK_PATHLOG"
    exit $_cx33_rc
    ;;
esac
exec "$CX33_MK_REAL" "$@"
CX33_SHIM_EOF
chmod +x "$CX33_SHIMDIR/mktemp"
CX33_PATH="$CX33_SHIMDIR:$STUB_PATH"

# Same healthy fixture CX30 builds and CX31 reuses — HEAD resolves and the tree is clean, so every
# git call in the run succeeds and the mktemp failure is the only thing wrong. codex-reviewer.sh
# issues bare `git ...`, never `git -C`, so the run happens inside that fixture; `cr()` never
# changes directory, so the `cd` is confined to a subshell exactly as CX28/CX30/CX31 do it.
CX33_FIXTURE_OK=1
if [ -z "$CX33_REAL_MKTEMP" ] || [ ! -x "$CX33_REAL_MKTEMP" ]; then CX33_FIXTURE_OK=0; fi
git -C "$CX30_HEALTHY_REPO" rev-parse --verify HEAD >/dev/null 2>&1 || CX33_FIXTURE_OK=0
if [ -n "$(git -C "$CX30_HEALTHY_REPO" status --porcelain 2>/dev/null)" ]; then CX33_FIXTURE_OK=0; fi

CX33_CTL_OUT="$WORK/cx33-control.json"
CX33_CTL_ERRF="$WORK/cx33-control.err"
CX33_CTL_COUNTF="$WORK/cx33-control.count"
rm -f "$CX33_CTL_OUT" "$CX33_CTL_COUNTF" "$WORK/cx33-control.fired"
: > "$WORK/cx33-control.paths"
set_stub "$MINIMAL_PAYLOAD" ""
( cd "$CX30_HEALTHY_REPO" && PATH="$CX33_PATH" CX33_MK_REAL="$CX33_REAL_MKTEMP" \
    CX33_MK_COUNT="$CX33_CTL_COUNTF" CX33_MK_FIRED="$WORK/cx33-control.fired" \
    CX33_MK_PATHLOG="$WORK/cx33-control.paths" CX33_MK_FAIL_NTH=0 \
    bash "$CR" --mode audit --dimension structure --diff-scope uncommitted --out "$CX33_CTL_OUT" ) \
    >/dev/null 2>"$CX33_CTL_ERRF"
CX33_CTL_RC=$?
CX33_CTL_ERR=$(cat "$CX33_CTL_ERRF")
CX33_CTL_N=0
[ -f "$CX33_CTL_COUNTF" ] && CX33_CTL_N=$(cat "$CX33_CTL_COUNTF")
CX33_CTL_EMPTY_ARRAY=0
if [ -s "$CX33_CTL_OUT" ] && grep -q -F '[]' "$CX33_CTL_OUT"; then CX33_CTL_EMPTY_ARRAY=1; fi

CX33_RAN=0
CX33_BAD=""
for _cx33_nth in 1 2; do
  case "$_cx33_nth" in
    1) _cx33_tail="whole-tree list"; _cx33_want_made=0 ;;
    *) _cx33_tail="changed-paths list"; _cx33_want_made=1 ;;
  esac
  CX33_RAN=$((CX33_RAN + 1))
  _cx33_out="$WORK/cx33-$_cx33_nth.json"
  _cx33_errf="$WORK/cx33-$_cx33_nth.err"
  _cx33_countf="$WORK/cx33-$_cx33_nth.count"
  _cx33_firedf="$WORK/cx33-$_cx33_nth.fired"
  _cx33_pathsf="$WORK/cx33-$_cx33_nth.paths"
  rm -f "$_cx33_out" "$_cx33_countf" "$_cx33_firedf"
  : > "$_cx33_pathsf"
  set_stub "$MINIMAL_PAYLOAD" ""
  ( cd "$CX30_HEALTHY_REPO" && PATH="$CX33_PATH" CX33_MK_REAL="$CX33_REAL_MKTEMP" \
      CX33_MK_COUNT="$_cx33_countf" CX33_MK_FIRED="$_cx33_firedf" \
      CX33_MK_PATHLOG="$_cx33_pathsf" CX33_MK_FAIL_NTH="$_cx33_nth" \
      bash "$CR" --mode audit --dimension structure --diff-scope uncommitted --out "$_cx33_out" ) \
      >/dev/null 2>"$_cx33_errf"
  _cx33_rc=$?
  _cx33_err=$(cat "$_cx33_errf")
  _cx33_made=$(wc -l < "$_cx33_pathsf" | tr -d ' ')
  _cx33_why=""
  [ -f "$_cx33_firedf" ] || _cx33_why="$_cx33_why shim-never-fired"
  [ "$_cx33_rc" -eq 3 ] || _cx33_why="$_cx33_why rc=$_cx33_rc(want-3)"
  printf '%s' "$_cx33_err" | grep -q -F 'DID-NOT-RUN' || _cx33_why="$_cx33_why no-DID-NOT-RUN"
  printf '%s' "$_cx33_err" | grep -q -F 'could not create the temporary file' \
    || _cx33_why="$_cx33_why no-mktemp-reason"
  printf '%s' "$_cx33_err" | grep -q -F "for the $_cx33_tail" \
    || _cx33_why="$_cx33_why wrong-call-isolated(want:$_cx33_tail)"
  [ ! -s "$_cx33_out" ] || _cx33_why="$_cx33_why artifact-written"
  [ "$_cx33_made" = "$_cx33_want_made" ] \
    || _cx33_why="$_cx33_why temp-files-created=$_cx33_made(want-$_cx33_want_made)"
  while IFS= read -r _cx33_p; do
    [ -n "$_cx33_p" ] || continue
    if [ -e "$_cx33_p" ]; then _cx33_why="$_cx33_why leaked-temp-file"; fi
  done < "$_cx33_pathsf"
  if [ -n "$_cx33_why" ]; then
    CX33_BAD="$CX33_BAD [call-$_cx33_nth:$_cx33_why ]"
  fi
done

if [ "$CX33_FIXTURE_OK" -eq 1 ] && [ "$CX33_CTL_RC" -eq 0 ] && [ "$CX33_CTL_N" = "2" ] \
   && [ "$CX33_CTL_EMPTY_ARRAY" -eq 1 ] && [ "$CX33_RAN" -eq 2 ] && [ -z "$CX33_BAD" ]; then
  ok "CX33: audit mode — a failing mktemp for the whole-tree list, and one for the changed-paths list, each exit 3 (DID-NOT-RUN) naming which temp file could not be created, write no --out artifact and leak no temp file (loop ran $CX33_RAN times); with mktemp healthy the same fixture still exits 0 with an empty findings array"
else
  bad "CX33: audit-mode mktemp failure handling — fixture-ok=$CX33_FIXTURE_OK control-rc=$CX33_CTL_RC (want 0) control-mktemp-calls-from-codex-reviewer=$CX33_CTL_N (want 2) control-empty-array=$CX33_CTL_EMPTY_ARRAY control-stderr=${CX33_CTL_ERR:-none} loop-ran=$CX33_RAN (need 2) failing-calls:${CX33_BAD:-none}"
fi
# plant: CX33 | plugin/scripts/codex-reviewer.sh | if [ "$_mktemp_rc" -ne 0 ] || [ -z "$ALL_FILES_FILE" ]; then | if false; then
# plant: CX33 | plugin/scripts/codex-reviewer.sh | if [ "$_mktemp_rc" -ne 0 ] || [ -z "$CHANGED_FILES_FILE" ]; then | if false; then

# CX34 (R-01) — the two `printf` WRITES and the `grep -Fxf` INTERSECTION that follow the mktemp pair
# CX33 pins, none of which captured its exit status until the fix this pins. This is exactly the
# residual CX33's own fixture cannot reach: a `mktemp` that SUCCEEDS and a write that fails
# afterwards (the filesystem filling between the two calls), or an intersection that fails for an
# I/O reason. Each of the three left FILE_LIST empty, and the empty-result branch reported that as a
# clean audit — exit 0 with `[]` at --out, indistinguishable from a genuinely empty diff (rule 7),
# the same shape CX28, CX31 and CX33 pin at three earlier points in this one block.
#
# THREE ARMS, THREE INJECTIONS, because the three steps fail for different reasons and no single
# injection produces all three:
#   - the two writes fail because their target PATH is unwritable, never because mktemp failed. The
#     shim hands back a syntactically fine path inside a `chmod 555` directory and EXITS 0, so the
#     mktemp guard above passes (status 0, variable non-empty) and bash's redirection is what fails.
#     That is deliberately the OPPOSITE of CX33's shim, which fails mktemp itself; the two are kept
#     as separate shims rather than merged because they answer different questions (rule 6) and a
#     shared one that broke would disable both assertions at once.
#   - the intersection fails through a `grep` shim that exits 2 ONLY when it sees the literal `-Fxf`
#     flag this call site uses, passing straight through to the real grep otherwise so nothing else
#     in the run changes behaviour. grep's own contract makes exit 0 (matched) and exit 1 (no match)
#     legitimate silent successes, so a status ABOVE 1 is the only one that may be treated as a
#     failure — and the control run below asserts the `-Fxf` invocation count is exactly 1 rather
#     than assuming the call site is unique (rule 7).
# The mktemp shim selects its victim by CALLER and not by a global ordinal, for the reason spelled
# out at CX33: enumerate-sources.sh runs first and calls mktemp twice on its own account.
#
# THE MESSAGE IS ASSERTED, NEVER JUST THE CODE. All three arms exit 3 and this script has many
# exit-3 paths, so `rc -eq 3` alone pins nothing (CX32's lesson): each arm requires the tail naming
# WHICH step failed — "write the whole-tree list" / "write the changed-paths list" / "intersect the
# whole-tree and changed-paths lists" — plus the captured-status token ("printf exit" / "grep exit")
# that only exists because the status was captured. The tail is also the only proof the injection
# isolated the step the arm claims: with the wrong step failing, the run still exits 3.
#
# stderr is asserted by CONTAINMENT, never equality, and the asymmetry behind that is measured, not
# assumed: on a failed write bash's own "<path>: Permission denied" redirection diagnostic reaches
# stderr beside the DID-NOT-RUN line, while on a failed intersection the shim's stderr is swallowed
# by the `2>/dev/null` on that line, leaving the script's own message as the sole evidence.
#
# BOTH DIRECTIONS (rule 8) via the control run, which is NOT a duplicate of CX33's: CX33's control
# proves an EMPTY diff still exits 0 with `[]`, this one proves a NON-EMPTY intersection is really
# computed. Its fixture is a repository with one MODIFIED tracked file and one untouched one, so the
# prompt handed to the stub `codex` must name the changed file and must NOT name the untouched one —
# a whole-tree fallback and a collapsed intersection each fail that. The --out artifact cannot carry
# this evidence: with an empty findings payload the real path writes `[]`, byte-identical to what
# the empty-result short circuit writes, so the PROMPT is the only place the two outcomes differ.
CX34_SHIMDIR="$WORK/cx34-shim"
mkdir -p "$CX34_SHIMDIR"
CX34_REAL_MKTEMP=$(command -v mktemp 2>/dev/null)
CX34_REAL_GREP=$(command -v grep 2>/dev/null)
cat > "$CX34_SHIMDIR/mktemp" <<'CX34_MK_SHIM_EOF'
#!/bin/bash
# Caller-selective mktemp shim for CX34 in codex-audit-mode.test.sh. Unlike CX33's it always
# SUCCEEDS: on the Nth call made by codex-reviewer.sh itself it prints a path inside a read-only
# directory and exits 0, so the mktemp guard passes and the WRITE that follows is what fails.
# Placed first on a PATH handed ONLY to the codex-reviewer.sh subprocess under test.
set -u
_cx34_parent=$(ps -o args= -p $PPID 2>/dev/null)
case "$_cx34_parent" in
  *codex-reviewer.sh*)
    _cx34_n=0
    if [ -f "${CX34_MK_COUNT:-/nonexistent}" ]; then _cx34_n=$(cat "$CX34_MK_COUNT"); fi
    _cx34_n=$((_cx34_n + 1))
    printf '%s\n' "$_cx34_n" > "$CX34_MK_COUNT"
    if [ "$_cx34_n" = "${CX34_MK_BAD_NTH:-0}" ]; then
      printf '%s\n' "$_cx34_n" > "$CX34_MK_FIRED"
      printf '%s\n' "$CX34_MK_BADPATH"
      exit 0
    fi
    # Not `exec`: the real path handed back is logged, so the arms below can check that a temp file
    # created BEFORE the failing step is removed on the way out rather than leaked.
    _cx34_made=$("$CX34_MK_REAL" "$@")
    _cx34_rc=$?
    printf '%s\n' "$_cx34_made"
    printf '%s\n' "$_cx34_made" >> "$CX34_MK_PATHLOG"
    exit $_cx34_rc
    ;;
esac
exec "$CX34_MK_REAL" "$@"
CX34_MK_SHIM_EOF
chmod +x "$CX34_SHIMDIR/mktemp"
cat > "$CX34_SHIMDIR/grep" <<'CX34_GREP_SHIM_EOF'
#!/bin/bash
# Flag-selective grep shim for CX34. Every invocation carrying the literal `-Fxf` is COUNTED (the
# control run's denominator), and failed with exit 2 only when armed. Everything else — including
# enumerate-sources.sh's own `grep -v -E` and codex-reviewer.sh's rate-limit scan — passes straight
# through to the real grep, so nothing outside the call site under test changes behaviour.
set -u
for _cx34_arg in "$@"; do
  if [ "$_cx34_arg" = "-Fxf" ]; then
    printf 'Fxf\n' >> "$CX34_GREP_SEEN"
    if [ "${CX34_GREP_FAIL:-0}" = "1" ]; then
      printf 'Fxf\n' > "$CX34_GREP_FIRED"
      printf 'cx34 grep shim: deliberate exit 2 on the -Fxf intersection\n' >&2
      exit 2
    fi
    break
  fi
done
exec "$CX34_GREP_REAL" "$@"
CX34_GREP_SHIM_EOF
chmod +x "$CX34_SHIMDIR/grep"
CX34_PATH="$CX34_SHIMDIR:$STUB_PATH"

# A repository with ONE modified tracked file and one untouched one. CX30's healthy fixture cannot
# serve here: it is deliberately CLEAN, and CX31 and CX33 both assert that cleanliness.
CX34_REPO="$WORK/cx34-changed-repo"
mkdir -p "$CX34_REPO"
git init -q "$CX34_REPO" >/dev/null 2>&1
printf 'let cx34a = 1\n' > "$CX34_REPO/cx34-changed.swift"
printf 'let cx34b = 2\n' > "$CX34_REPO/cx34-untouched.swift"
git -C "$CX34_REPO" add cx34-changed.swift cx34-untouched.swift >/dev/null 2>&1
git -C "$CX34_REPO" -c user.email=cx34@example.invalid -c user.name=cx34 \
    -c commit.gpgsign=false commit -q -m "cx34 fixture" >/dev/null 2>&1
printf 'let cx34a = 2\n' > "$CX34_REPO/cx34-changed.swift"

CX34_RODIR="$WORK/cx34-readonly"
mkdir -p "$CX34_RODIR"
chmod 555 "$CX34_RODIR"
CX34_BADPATH="$CX34_RODIR/cx34-nowrite.tmp"

# Denominator guards (rule 7) — each one is a way the arms below could pass or fail for a reason
# unrelated to the mechanism they name.
CX34_FIXTURE_OK=1
if [ -z "$CX34_REAL_MKTEMP" ] || [ ! -x "$CX34_REAL_MKTEMP" ]; then CX34_FIXTURE_OK=0; fi
if [ -z "$CX34_REAL_GREP" ] || [ ! -x "$CX34_REAL_GREP" ]; then CX34_FIXTURE_OK=0; fi
git -C "$CX34_REPO" rev-parse --verify HEAD >/dev/null 2>&1 || CX34_FIXTURE_OK=0
# EXACTLY one changed path, and it is the one the control run expects to find in the prompt: with no
# changes "a non-empty intersection" would be vacuous, and with two the "untouched file is absent"
# half would pass for the wrong reason.
CX34_DIFF_NAMES=$(git -C "$CX34_REPO" diff HEAD --name-only 2>/dev/null)
[ "$CX34_DIFF_NAMES" = "cx34-changed.swift" ] || CX34_FIXTURE_OK=0
# The read-only directory must really be unwritable. On a runner where it is not (root, or a
# filesystem ignoring the mode) the two write arms would exercise nothing, and that must read as a
# FAILURE here, never as a pass.
if ( : > "$CX34_RODIR/cx34-probe" ) 2>/dev/null; then
  CX34_FIXTURE_OK=0
  rm -f "$CX34_RODIR/cx34-probe"
fi

CX34_CTL_OUT="$WORK/cx34-control.json"
CX34_CTL_ERRF="$WORK/cx34-control.err"
CX34_CTL_COUNTF="$WORK/cx34-control.count"
CX34_CTL_PROMPT="$WORK/cx34-control-prompt.txt"
CX34_CTL_SEENF="$WORK/cx34-control.grepseen"
rm -f "$CX34_CTL_OUT" "$CX34_CTL_COUNTF" "$CX34_CTL_PROMPT" \
      "$WORK/cx34-control.mkfired" "$WORK/cx34-control.grepfired"
: > "$WORK/cx34-control.paths"
: > "$CX34_CTL_SEENF"
set_stub "$MINIMAL_PAYLOAD" "$CX34_CTL_PROMPT"
( cd "$CX34_REPO" && PATH="$CX34_PATH" CX34_MK_REAL="$CX34_REAL_MKTEMP" \
    CX34_GREP_REAL="$CX34_REAL_GREP" CX34_MK_COUNT="$CX34_CTL_COUNTF" \
    CX34_MK_FIRED="$WORK/cx34-control.mkfired" CX34_MK_PATHLOG="$WORK/cx34-control.paths" \
    CX34_MK_BADPATH="$CX34_BADPATH" CX34_MK_BAD_NTH=0 CX34_GREP_SEEN="$CX34_CTL_SEENF" \
    CX34_GREP_FIRED="$WORK/cx34-control.grepfired" CX34_GREP_FAIL=0 \
    bash "$CR" --mode audit --dimension structure --diff-scope uncommitted --out "$CX34_CTL_OUT" ) \
    >/dev/null 2>"$CX34_CTL_ERRF"
CX34_CTL_RC=$?
CX34_CTL_ERR=$(cat "$CX34_CTL_ERRF")
CX34_CTL_FXF=$(wc -l < "$CX34_CTL_SEENF" | tr -d ' ')
CX34_CTL_MK_N=0
[ -f "$CX34_CTL_COUNTF" ] && CX34_CTL_MK_N=$(cat "$CX34_CTL_COUNTF")
CX34_CTL_PROMPT_OK=0
if [ -s "$CX34_CTL_PROMPT" ] && grep -q -F 'cx34-changed.swift' "$CX34_CTL_PROMPT" \
   && ! grep -q -F 'cx34-untouched.swift' "$CX34_CTL_PROMPT"; then
  CX34_CTL_PROMPT_OK=1
fi

CX34_RAN=0
CX34_BAD=""
for _cx34_case in write-whole-tree write-changed-paths intersect; do
  # `want_made` is the number of REAL temp files the run allocates before it dies: the write arms
  # substitute an unwritable path for one of the two, the intersect arm allocates both.
  case "$_cx34_case" in
    write-whole-tree)
      _cx34_nth=1; _cx34_gfail=0; _cx34_want_made=1; _cx34_status_token="printf exit"
      _cx34_tail="could not write the whole-tree list to its temporary file" ;;
    write-changed-paths)
      _cx34_nth=2; _cx34_gfail=0; _cx34_want_made=1; _cx34_status_token="printf exit"
      _cx34_tail="could not write the changed-paths list to its temporary file" ;;
    *)
      _cx34_nth=0; _cx34_gfail=1; _cx34_want_made=2; _cx34_status_token="grep exit"
      _cx34_tail="could not intersect the whole-tree and changed-paths lists" ;;
  esac
  CX34_RAN=$((CX34_RAN + 1))
  _cx34_out="$WORK/cx34-$_cx34_case.json"
  _cx34_errf="$WORK/cx34-$_cx34_case.err"
  _cx34_countf="$WORK/cx34-$_cx34_case.count"
  _cx34_mkfiredf="$WORK/cx34-$_cx34_case.mkfired"
  _cx34_gfiredf="$WORK/cx34-$_cx34_case.grepfired"
  _cx34_pathsf="$WORK/cx34-$_cx34_case.paths"
  _cx34_seenf="$WORK/cx34-$_cx34_case.grepseen"
  rm -f "$_cx34_out" "$_cx34_countf" "$_cx34_mkfiredf" "$_cx34_gfiredf"
  : > "$_cx34_pathsf"
  : > "$_cx34_seenf"
  set_stub "$MINIMAL_PAYLOAD" ""
  ( cd "$CX34_REPO" && PATH="$CX34_PATH" CX34_MK_REAL="$CX34_REAL_MKTEMP" \
      CX34_GREP_REAL="$CX34_REAL_GREP" CX34_MK_COUNT="$_cx34_countf" \
      CX34_MK_FIRED="$_cx34_mkfiredf" CX34_MK_PATHLOG="$_cx34_pathsf" \
      CX34_MK_BADPATH="$CX34_BADPATH" CX34_MK_BAD_NTH="$_cx34_nth" CX34_GREP_SEEN="$_cx34_seenf" \
      CX34_GREP_FIRED="$_cx34_gfiredf" CX34_GREP_FAIL="$_cx34_gfail" \
      bash "$CR" --mode audit --dimension structure --diff-scope uncommitted --out "$_cx34_out" ) \
      >/dev/null 2>"$_cx34_errf"
  _cx34_rc=$?
  _cx34_err=$(cat "$_cx34_errf")
  _cx34_made=$(wc -l < "$_cx34_pathsf" | tr -d ' ')
  _cx34_mkn=0
  [ -f "$_cx34_countf" ] && _cx34_mkn=$(cat "$_cx34_countf")
  # WHICH shim fired is asserted in both directions: a run that died at the other injection point
  # would also exit 3, and must not be credited to this arm.
  if [ "$_cx34_gfail" = "1" ]; then
    _cx34_wantfired="$_cx34_gfiredf"; _cx34_notfired="$_cx34_mkfiredf"
  else
    _cx34_wantfired="$_cx34_mkfiredf"; _cx34_notfired="$_cx34_gfiredf"
  fi
  _cx34_why=""
  [ -f "$_cx34_wantfired" ] || _cx34_why="$_cx34_why shim-never-fired"
  [ ! -f "$_cx34_notfired" ] || _cx34_why="$_cx34_why wrong-shim-fired"
  [ "$_cx34_rc" -eq 3 ] || _cx34_why="$_cx34_why rc=$_cx34_rc(want-3)"
  printf '%s' "$_cx34_err" | grep -q -F 'DID-NOT-RUN' || _cx34_why="$_cx34_why no-DID-NOT-RUN"
  printf '%s' "$_cx34_err" | grep -q -F "$_cx34_tail" \
    || _cx34_why="$_cx34_why wrong-step-named(want:$_cx34_tail)"
  printf '%s' "$_cx34_err" | grep -q -F "$_cx34_status_token" \
    || _cx34_why="$_cx34_why status-not-reported(want:$_cx34_status_token)"
  [ ! -s "$_cx34_out" ] || _cx34_why="$_cx34_why artifact-written"
  [ "$_cx34_mkn" = "2" ] || _cx34_why="$_cx34_why mktemp-calls-from-codex-reviewer=$_cx34_mkn(want-2)"
  [ "$_cx34_made" = "$_cx34_want_made" ] \
    || _cx34_why="$_cx34_why real-temp-files-created=$_cx34_made(want-$_cx34_want_made)"
  while IFS= read -r _cx34_p; do
    [ -n "$_cx34_p" ] || continue
    if [ -e "$_cx34_p" ]; then _cx34_why="$_cx34_why leaked-temp-file"; fi
  done < "$_cx34_pathsf"
  if [ -n "$_cx34_why" ]; then
    CX34_BAD="$CX34_BAD [$_cx34_case:$_cx34_why ]"
  fi
done
# Restored so the suite's own EXIT trap can remove $WORK; the arms above are finished with it.
chmod 755 "$CX34_RODIR"

# `CX34_CTL_MK_N -ge 2` is a VACUITY guard only and is deliberately not an exact count (rule 10):
# the control run reaches `codex exec`, so it allocates the schema/prompt/raw-output temp files too
# and an exact number here would pin codex-reviewer.sh's downstream internals, which this assertion
# is not about. The exact per-run count that matters — two mktemp calls before the guard fires — is
# asserted inside each arm, where the run stops at the step being pinned.
if [ "$CX34_FIXTURE_OK" -eq 1 ] && [ "$CX34_CTL_RC" -eq 0 ] && [ "$CX34_CTL_PROMPT_OK" -eq 1 ] \
   && [ "$CX34_CTL_FXF" = "1" ] && [ "$CX34_CTL_MK_N" -ge 2 ] && [ "$CX34_RAN" -eq 3 ] \
   && [ -z "$CX34_BAD" ]; then
  ok "CX34: audit mode — a failed write of the whole-tree list, a failed write of the changed-paths list and a failed grep -Fxf intersection each exit 3 (DID-NOT-RUN) naming which step failed and its captured status, write no --out artifact and leak no temp file (loop ran $CX34_RAN times); with all three healthy the same fixture computes a real intersection, exits 0 and hands codex a prompt naming the changed file and not the untouched one"
else
  bad "CX34: audit-mode write/intersection failure handling — fixture-ok=$CX34_FIXTURE_OK control-rc=$CX34_CTL_RC (want 0) control-prompt-is-the-intersection=$CX34_CTL_PROMPT_OK control-Fxf-invocations=$CX34_CTL_FXF (want 1) control-mktemp-calls-from-codex-reviewer=$CX34_CTL_MK_N (want >= 2) control-stderr=${CX34_CTL_ERR:-none} loop-ran=$CX34_RAN (need 3) failing-steps:${CX34_BAD:-none}"
fi
# plant: CX34 | plugin/scripts/codex-reviewer.sh | if [ "$_write_rc" -ne 0 ]; then echo "codex-reviewer: DID-NOT-RUN: could not write the whole-tree list | if false; then echo "codex-reviewer: DID-NOT-RUN: could not write the whole-tree list
# plant: CX34 | plugin/scripts/codex-reviewer.sh | if [ "$_write_rc" -ne 0 ]; then echo "codex-reviewer: DID-NOT-RUN: could not write the changed-paths list | if false; then echo "codex-reviewer: DID-NOT-RUN: could not write the changed-paths list
# plant: CX34 | plugin/scripts/codex-reviewer.sh | if [ "$_grep_rc" -gt 1 ]; then | if false; then

# =====================================================================================
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 35 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 35) — a floor only, it absorbs its own plant (rule 10); S0 + CX01-CX34 are the frozen identity set"
  PASS=$((PASS + 1))
else
  echo "FAIL: Z1: only $_total assertions ran — expected >= 35; assertions vanished"
  FAIL=$((FAIL + 1))
fi
[ "$FAIL" -eq 0 ]
