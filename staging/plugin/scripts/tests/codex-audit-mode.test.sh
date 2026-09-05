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
# deliberately never writes any of those three as a literal token: spec-coverage.sh's own
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
# FIFTEEN `# plant:` declarations sit beside CX02, CX05, CX10, CX12, CX13, CX14, CX15, CX17, CX18,
# CX20, CX21, CX22, CX23, CX24 and CX26 (rule 2 — an assertion nobody planted pins nothing). The
# ones targeting Task 2's argument surface (CX02, CX05) and the SKILL.md prose Tasks 6-8 add
# (CX20-CX24, CX26) are grounded in literal text the plan or the source files already state
# verbatim. The ones targeting Task 3/4's not-yet-written `codex-reviewer.sh` internals (CX10,
# CX12, CX13, CX17, CX18) are best-effort projections of that code's expected shape, following the
# file's own existing style; Task 9's plant run is explicitly budgeted (~10 lines) to repair a
# needle that turns out BADPLANT once the real code lands — "fix the needle, never the assertion"
# (plant-check.sh's own rule).
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
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 28 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 28) — a floor only, it absorbs its own plant (rule 10); CX01-CX27 are the frozen identity set"
  PASS=$((PASS + 1))
else
  echo "FAIL: Z1: only $_total assertions ran — expected >= 28; assertions vanished"
  FAIL=$((FAIL + 1))
fi
[ "$FAIL" -eq 0 ]
