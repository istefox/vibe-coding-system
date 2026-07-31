#!/bin/bash
# manifest-field-state.sh v1.0 — THE one place that answers "is this field present on this
# manifest, and if not, what era is the manifest from" (issue #195, ADR-0076).
#
# WHY THIS EXISTS. Fields are added to manifest-init.sh as ADDITIVE — no schema bump, no
# migration — so a manifest written before a field simply does not carry it. That is correct and
# deliberate (ADR-0016 for hook_verified, ADR-0039 for step5_review_mode). Then a checker gets
# written over the manifest corpus, reads the field with a one-liner, and cannot tell an ABSENT
# field from an INVALID one:
#
#     python3 -c "import yaml; m=yaml.safe_load(open('$m')); print(m.get('hook_verified'))"
#
# `m.get()` returns None for a field that is absent AND for one explicitly set to null, and the
# shell one-liner returns an empty string when the file could not be PARSED at all, because the
# traceback went to /dev/null. Issue #123 is what that costs: nightly-autopilot aborted a whole
# roadmap on two long-completed chains that merely predate the field, and told the operator they
# were "corrupted or hand-edited".
#
# IT REPORTS. IT DOES NOT DECIDE — and that separation is the whole design.
# The two call sites #123 fixed apply OPPOSITE defaults to the same absence, and both are right:
#   nightly-autopilot check 6   sweeps every manifest in the repo, most of them long completed.
#                               Absence on a completed chain is expected; that chain's dispatch
#                               mode cannot affect a future run. -> tolerate
#   autopilot-build   check 7   reads the ONE manifest about to be built, in flight by definition.
#                               Absence means nobody knows its dispatch mode. -> abort
# A helper that returned a verdict would have to flatten that asymmetry or grow a policy argument
# for it. It returns a FACT instead, and each caller keeps its own rule visible at its own site.
#
# The value domain is the caller's too, and it has to be: hook_verified is a boolean, step5_mode is
# workflow|agent_batch|null, step5_review_mode is none|checkpoint. There is no general "valid".
# (`agent_batch`, not `agent_fallback`: issue #240. The wrong name stood here from ADR-0076 until
# 2026-07-31 while 18 manifests carried the real one, and this comment is the worked example the
# next author of a step5_mode checker would have copied. ADR-0016 §Manifest fields had it right
# all along; the error entered in a SUMMARY of it and spread from there.)
#
# CONTRACT
#   stdout, exactly one line:
#     PRESENT|<value>        the field exists. <value> is python str() of the parsed YAML, so a
#                            YAML boolean reads True/False and anything else reads as its text.
#                            A QUOTED "true" therefore reads `true`, not `True`, and a caller
#                            asserting True/False rejects it — deliberate, and preserved from the
#                            one-liners this replaces.
#     ABSENT|<current_step>  the field is not in the mapping. <current_step> is the manifest's own,
#                            or empty if it has none. This is the era signal callers branch on.
#     UNREADABLE             the file is not parseable YAML, or does not parse to a mapping.
#   exit 0  a state was determined and printed (including UNREADABLE — that IS a determination)
#   exit 2  bad invocation, or the manifest is missing/unreadable as a FILE
#   exit 3  the check could not run: no python3, or no PyYAML. NOT the same as UNREADABLE, which
#           is a fact about the input; this is a fact about the environment (ADR-0046's exit-3
#           precedent, and #123's own lesson one level down).
#
# Callers split on the first `|` (`${st%%|*}` / `${st#*|}`). Newlines in a value are collapsed to
# spaces so the one-line contract holds; a value containing `|` is returned verbatim and the split
# on the FIRST separator still yields the whole value.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="manifest-field-state"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: manifest-field-state.sh <manifest.yml> <field>

Reports whether <field> is present on <manifest.yml>, and if not, the manifest's current_step.
Reports; never decides. The caller owns both the value domain and the absence policy.

stdout: PRESENT|<value> | ABSENT|<current_step> | UNREADABLE
Exit:   0 determined | 2 bad invocation or missing file | 3 could not run (no python3/PyYAML)
EOF
  exit 2
}

[ $# -eq 2 ] || usage "expected exactly 2 arguments, got $#"
MANIFEST="$1"
FIELD="$2"
[ -n "$MANIFEST" ] || usage "manifest path is empty"
[ -n "$FIELD" ] || usage "field name is empty"
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] \
  || { printf '%s: manifest not found or unreadable: %s\n' "$SELF" "$MANIFEST" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 \
  || { printf '%s: python3 not available — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }

# PyYAML is probed separately from the read, so "no parser" cannot be mistaken for "bad file".
python3 -c 'import yaml' >/dev/null 2>&1 \
  || { printf '%s: PyYAML not available — the check DID NOT RUN\n' "$SELF" >&2; exit 3; }

OUT=$(python3 -c '
import sys, yaml

def flat(v):
    return str(v).replace("\r", " ").replace("\n", " ")

path, field = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        m = yaml.safe_load(fh)
except Exception:
    print("UNREADABLE"); raise SystemExit(0)
if not isinstance(m, dict):
    print("UNREADABLE"); raise SystemExit(0)
if field not in m:
    cs = m.get("current_step")
    print("ABSENT|" + ("" if cs is None else flat(cs)))
else:
    print("PRESENT|" + flat(m[field]))
' "$MANIFEST" "$FIELD" 2>/dev/null)

# An empty result means python produced nothing rather than a state. Reporting that as a state
# would be the #123 defect reintroduced inside the thing that exists to prevent it.
[ -n "$OUT" ] || { printf '%s: no state produced for %s on %s — the check DID NOT RUN\n' \
  "$SELF" "$FIELD" "$MANIFEST" >&2; exit 3; }

printf '%s\n' "$OUT"
exit 0
