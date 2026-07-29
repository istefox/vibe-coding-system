#!/bin/bash
# h16-direction-check.sh v1.0 — H16 direction-check evidence reporter (issue #115; ADR-0061 §D2/§D3).
#
# CONTRACT: REPORTER, matching weakening-scan.sh / diff-budget-check.sh in this same family
# (ADR-0048 §D7's naming, restated at every call site since — do not copy a CHECKER idiom here,
# spec-coverage.sh/interface-check.sh branch on exit code, this script never does). Always exits
# 0. Signals through stdout only: the sentinel CLEAN on no finding, one or more TAB-separated
# TRIGGER lines otherwise. Never `[ -n "$out" ]` (true even on CLEAN — the same trap ADR-0048 §D7
# had to write out once already). H16 itself never blocks (ADR-0061 §D3): every input below is a
# heuristic, matching the "heuristics report, mechanical facts gate" line drawn four times already
# (ADR-0051 §D2, ADR-0053 §D2, ADR-0054 §D5, ADR-0058 §D4). The caller (project-conductor Step 5A)
# decides whether to ask; this script only decides whether there is evidence to ask about.
#
# WHAT THIS DOES NOT DO, STATED PLAINLY (issue #115 Task 4, decide-and-justify). ADR-0061 §D2 asks
# H16 to fire on "accumulated budget_findings overshoots ACROSS FEATURES", "repeated out-of-scope
# file findings", "a feature reaching amber or red at the tracer probe", and "suspect_findings
# recurring." Checked against what project-conductor can actually reach at its Step 5 seam:
#
#   - tracer_bullet_verdict is genuinely reachable ACROSS the whole roadmap. manifest-init.sh
#     (concept-to-code/scripts/manifest-init.sh, its `tracer_bullet_verdict: null` line — named,
#     not numbered, because the line number it used to carry pointed at an unrelated field)
#     writes it into each feature's OWN dated
#     manifest file under docs/manifests/ — one file per topic-slug, never overwritten by a later
#     feature. So the TRACER section below globs every manifest and genuinely accumulates this one
#     signal across features, exactly as ADR-0061 §D2 asks.
#   - budget_findings, out-of-scope findings and suspect_findings live ONLY in step5-report.json,
#     a SINGLE fixed path (<root>/.claude/step5-report.json) that the very next feature's own
#     Step 5 overwrites before project-conductor could ever compare two features' worth of it.
#     There is no archive of past reports. Building one would be a new persistent store — exactly
#     what issue #115's own plan forbids ("no new measurement and no new advisory array") and
#     exactly the risk ADR-0052 §D5 named. So for those three, this script does NOT accumulate
#     across features — it reads only the JUST-FINISHED feature's step5-report.json and looks for
#     WITHIN-FEATURE repetition (two or more budget overshoots, two or more out-of-scope hits, two
#     or more suspect_findings sharing a file or detector). That is real evidence, correctly
#     scoped to one feature, not a fabricated cross-feature count. If a future issue wants genuine
#     cross-feature accumulation for these three, it needs a persistence decision of its own —
#     not invented here.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="h16-direction-check"
usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: h16-direction-check.sh --root <project-root> --this-manifest <path> [--step5-report <path>]
stdout: CLEAN, or one or more TRIGGER<TAB><signal><TAB><evidence> lines.
Always exits 0 (reporter contract) -- a missing/unreadable input degrades to CLEAN, never fails.
EOF
}

ROOT=""; THIS_MANIFEST=""; S5=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { usage "--root needs a directory argument"; echo CLEAN; exit 0; }
      ROOT="$2"; shift 2 ;;
    --this-manifest)
      [ $# -ge 2 ] || { usage "--this-manifest needs a path argument"; echo CLEAN; exit 0; }
      THIS_MANIFEST="$2"; shift 2 ;;
    --step5-report)
      [ $# -ge 2 ] || { usage "--step5-report needs a path argument"; echo CLEAN; exit 0; }
      S5="$2"; shift 2 ;;
    *)
      usage "unknown argument: $1"; echo CLEAN; exit 0 ;;
  esac
done

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo CLEAN; exit 0
fi
[ -n "$S5" ] || S5="$ROOT/.claude/step5-report.json"

OUT=""

# ==================================================================================================
# TRACER — cross-feature, genuinely accumulated (see header). Every manifest under docs/manifests/
# that declares tracer_bullet_verdict amber or red counts toward the total, including the
# just-finished feature's manifest if it is among them (ADR-0057). A SINGLE amber/red feature is
# already evidence per ADR-0061 §D2's own wording ("a feature reaching amber or red"), so N>=1
# triggers — this is not a fixed-cadence counter, it is a count OF an actual signal, and it stays
# silent (contributes nothing) on a roadmap where every feature so far has been green.
# ==================================================================================================
if [ -d "$ROOT/docs/manifests" ]; then
  AMBER_RED_N=0
  for _m in "$ROOT"/docs/manifests/*.manifest.yml; do
    [ -f "$_m" ] || continue
    if grep -qE '^tracer_bullet_verdict: "(amber|red)"$' "$_m" 2>/dev/null; then
      AMBER_RED_N=$((AMBER_RED_N + 1))
    fi
  done
  if [ "$AMBER_RED_N" -ge 1 ]; then
    OUT="$OUT
TRIGGER	tracer-amber-red	$AMBER_RED_N feature(s) reached an amber/red tracer-bullet verdict (docs/manifests/*.manifest.yml)"
  fi
fi

# ==================================================================================================
# Same-feature signals from the JUST-FINISHED feature's step5-report.json only (see header for why
# these cannot be accumulated across features without a new store). jq missing, or the file
# missing/unreadable/malformed, degrades this section to contributing nothing — never a failure.
# ==================================================================================================
if [ -f "$S5" ] && command -v jq >/dev/null 2>&1; then
  BUDGET_N=$(jq '(.budget_findings // []) | length' "$S5" 2>/dev/null)
  case "${BUDGET_N:-}" in ''|*[!0-9]*) BUDGET_N=0 ;; esac

  OOS_N=$(jq '[(.budget_findings // [])[] | (.out_of_scope // []) | select(length > 0)] | length' "$S5" 2>/dev/null)
  case "${OOS_N:-}" in ''|*[!0-9]*) OOS_N=0 ;; esac

  # suspect_findings recurring in the same area: 2+ entries sharing a detector, OR 2+ sharing a
  # file, within THIS feature's diff (ADR-0051) — reachable without any cross-feature data at all.
  SUSPECT_DUP=$(jq -r '
    (.suspect_findings // []) as $s
    | ( [$s[].detector] | group_by(.) | map(select(length >= 2)) | length ) as $d
    | ( [$s[].file]     | group_by(.) | map(select(length >= 2)) | length ) as $f
    | ($d + $f)
  ' "$S5" 2>/dev/null)
  case "${SUSPECT_DUP:-}" in ''|*[!0-9]*) SUSPECT_DUP=0 ;; esac

  if [ "$BUDGET_N" -ge 2 ]; then
    OUT="$OUT
TRIGGER	budget-overshoot	$BUDGET_N budget_findings entries in the just-finished feature (step5-report.json) — same-feature evidence only, not accumulated across features (see header)"
  fi
  if [ "$OOS_N" -ge 2 ]; then
    OUT="$OUT
TRIGGER	out-of-scope	$OOS_N task(s) in the just-finished feature touched files outside their declared scope (budget_findings[].out_of_scope) — same-feature evidence only, not accumulated across features (see header)"
  fi
  if [ "$SUSPECT_DUP" -ge 1 ]; then
    OUT="$OUT
TRIGGER	suspect-recurring	suspect_findings recur by detector or file in the just-finished feature (step5-report.json)"
  fi
fi

OUT=$(printf '%s\n' "$OUT" | sed '/^$/d')
if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
else
  echo CLEAN
fi
exit 0
