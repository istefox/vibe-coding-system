#!/bin/bash
# ci-tier v1.0 — plant-registry-derived CI tier CHECKER (issue #529 follow-up; VCS-051, ADR-0180).
#
# CONTRACT. This is a CHECKER (branched on by exit code, rule 5) — never a reporter. It decides a
# policy value (which CI tier a commit needs), not merely reports findings.
#
#   ci-tier.sh --classify <changed-files-file>   one repo-relative path per line
#     stdout  TIER: docs|standard|full
#             PLANT-MATCH: <path>   (one per changed file that is a declared plant target — lets a
#                                     caller render "these files are why: ...")
#     exit 0  classification succeeded
#     exit 2  bad invocation (missing/unreadable <changed-files-file>, unknown flag)
#     exit 3  DID-NOT-RUN — the plant registry directory could not be read, the derived
#             plant-target set is empty, or a declared plant-target path failed to resolve on
#             disk. Printed to stderr as `DID-NOT-RUN: <reason>`. This is NOT a clean `docs`
#             result (rule 4: "did not run" is not "found nothing") — callers MUST treat exit 3 as
#             tier `full`, the expensive, safe option, never silently.
#
#   ci-tier.sh --resolve <requested-tier> <computed-tier>
#     stdout  TIER: <effective-tier>
#     stderr  DOWNGRADED-BY-REQUEST: requested=<x> computed=<y>   (only when the request asked for
#             something cheaper than the computed floor)
#     exit 0  always — this call never refuses to run; the floor is enforced by ALWAYS printing the
#             stricter of the two tiers as the effective one, informational note or not
#     exit 2  bad invocation (missing argument, an unrecognised tier name)
#
# WHY THE RULE LIVES HERE AND NOT IN A WORKFLOW YAML `if:` (ADR-0180). plant-check.sh's own
# --require-legs block states why `.github/` is "not a legal plant TARGET": "logic that lives
# only in yaml can be asserted to exist and never to work" (rule 16). This classification is
# therefore ordinary shell, plantable like every other script in this directory —
# ci-tier.test.sh's CT-DENOM assertion proves the denominator guard actually fires by forcing the
# registry empty and watching the exit code.
#
# WHY THE TIER IS DERIVED FROM THE PLANT REGISTRY, NOT A HAND-WRITTEN PATH HEURISTIC. Measured
# against this repository (ADR-0180): the plant registry declares 100 distinct targets, 11 of them
# under docs/ — including docs/chain-decisions.md and docs/chain-decision-index.md — so a naive
# "docs/ is prose, skip the heavy jobs" rule would silently skip the registry's own verification
# targets the moment a docs-only PR touched one.
#
# THE CLASSIFICATION RULE, applied to the changed-file set:
#   changed intersect plant-targets        != {}  -> full
#   else changed intersect (staging/** union .github/** union .claude/**) != {} -> standard
#   else                                                 -> docs
#
# CI_TIER_REGISTRY_DIR overrides where `# plant:` declarations are read from (default:
# <this script's staging/>/plugin/scripts/tests/) — the mechanism the test suite uses to force an
# empty-registry DID-NOT-RUN without touching the real one. Not read outside --classify.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="ci-tier"
HERE=$(cd "$(dirname "$0")" && pwd)          # .../staging/plugin/scripts
STAGING=$(cd "$HERE/../.." && pwd)           # .../staging
REPO=$(cd "$STAGING/.." && pwd)

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: ci-tier.sh --classify <changed-files-file>     one repo-relative path per line
       ci-tier.sh --resolve <requested-tier> <computed-tier>

--classify: prints TIER: docs|standard|full and PLANT-MATCH: <path> evidence lines.
            exit 0 classified | 2 bad invocation | 3 could not classify (caller must treat as full)
--resolve:  prints the effective tier, never below the computed floor (full > standard > docs).
            exit 0 always | 2 bad invocation (unrecognised tier name).
EOF
}

strictness() {
  case "$1" in
    full)     echo 3 ;;
    standard) echo 2 ;;
    docs)     echo 1 ;;
    *)        echo 0 ;;
  esac
}

REGISTRY_DIR="${CI_TIER_REGISTRY_DIR:-$STAGING/plugin/scripts/tests}"

# classify <changed-files-file> — never returns; exits 0/2/3 directly.
classify() {
  CHFILE="${1:-}"
  [ -n "$CHFILE" ] || { usage "--classify needs a changed-files-file argument"; exit 2; }
  [ -r "$CHFILE" ] || { usage "cannot read changed-files file: $CHFILE"; exit 2; }

  if [ ! -d "$REGISTRY_DIR" ] || [ ! -r "$REGISTRY_DIR" ]; then
    printf '%s: DID-NOT-RUN: plant registry directory is unreadable: %s\n' "$SELF" "$REGISTRY_DIR" >&2
    exit 3
  fi

  TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT

  # --- derive the plant-target set (the plan's stated rule, verbatim) ----------------------------
  RAW="$TMPD/raw"
  grep -rh "^# plant:" "$REGISTRY_DIR" 2>/dev/null \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "") print $2 }' \
    | sort -u >"$RAW"

  if [ ! -s "$RAW" ]; then
    printf '%s: DID-NOT-RUN: derived plant-target set is empty under %s\n' "$SELF" "$REGISTRY_DIR" >&2
    exit 3
  fi

  # --- resolve each declared entry to a repo-relative path, mirroring plant-check.sh's own PATH
  # RESOLUTION exactly: staging-relative by default, a literal `../docs/` prefix reaches docs/, any
  # other `..` is refused (treated the same as a target that fails to resolve). ---------------------
  TARGETS="$TMPD/targets"; : >"$TARGETS"
  UNRESOLVED=""
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      ../docs/*)
        case "${entry#../docs/}" in
          *..*) UNRESOLVED="$UNRESOLVED $entry"; continue ;;
        esac
        rel="docs/${entry#../docs/}" ;;
      *..*)
        UNRESOLVED="$UNRESOLVED $entry"; continue ;;
      *)
        rel="staging/$entry" ;;
    esac
    if [ ! -f "$REPO/$rel" ]; then
      UNRESOLVED="$UNRESOLVED $entry"
      continue
    fi
    printf '%s\n' "$rel" >>"$TARGETS"
  done <"$RAW"

  if [ -n "$UNRESOLVED" ]; then
    printf '%s: DID-NOT-RUN: plant-target path(s) failed to resolve on disk:%s\n' \
      "$SELF" "$UNRESOLVED" >&2
    exit 3
  fi

  # --- classify the changed-file set against the resolved target set -----------------------------
  MATCHES="$TMPD/matches"; : >"$MATCHES"
  FULL_HIT=0
  while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    if grep -qxF "$cf" "$TARGETS"; then
      FULL_HIT=1
      printf '%s\n' "$cf" >>"$MATCHES"
    fi
  done <"$CHFILE"

  if [ "$FULL_HIT" -eq 1 ]; then
    TIER="full"
  else
    STANDARD_HIT=0
    while IFS= read -r cf; do
      [ -n "$cf" ] || continue
      case "$cf" in
        staging/*|.github/*|.claude/*) STANDARD_HIT=1 ;;
      esac
    done <"$CHFILE"
    if [ "$STANDARD_HIT" -eq 1 ]; then TIER="standard"; else TIER="docs"; fi
  fi

  printf 'TIER: %s\n' "$TIER"
  if [ -s "$MATCHES" ]; then
    while IFS= read -r m; do
      printf 'PLANT-MATCH: %s\n' "$m"
    done <"$MATCHES"
  fi
  exit 0
}

# resolve <requested-tier> <computed-tier> — never returns; always exits 0 (or 2 on a bad name).
resolve() {
  req="${1:-}"; comp="${2:-}"
  [ -n "$req" ] && [ -n "$comp" ] || { usage "--resolve needs <requested-tier> <computed-tier>"; exit 2; }
  req_s=$(strictness "$req")
  comp_s=$(strictness "$comp")
  [ "$req_s" -ge 1 ] || { usage "unrecognised requested tier: $req"; exit 2; }
  [ "$comp_s" -ge 1 ] || { usage "unrecognised computed tier: $comp"; exit 2; }

  if [ "$req_s" -ge "$comp_s" ]; then
    eff="$req"
  else
    eff="$comp"
    printf 'DOWNGRADED-BY-REQUEST: requested=%s computed=%s\n' "$req" "$comp" >&2
  fi
  printf 'TIER: %s\n' "$eff"
  exit 0
}

[ $# -ge 1 ] || { usage "one of --classify or --resolve is required"; exit 2; }
MODE="$1"; shift

case "$MODE" in
  --classify)
    [ $# -eq 1 ] || { usage "--classify takes exactly one argument"; exit 2; }
    classify "$1" ;;
  --resolve)
    [ $# -eq 2 ] || { usage "--resolve takes exactly two arguments"; exit 2; }
    resolve "$1" "$2" ;;
  *)
    usage "unknown argument: $MODE"; exit 2 ;;
esac
