#!/bin/bash
# spec-coverage-lookup.sh v1.0 — resolves whether an issue already has a SPEC on disk, and which
# one (issue #414 / ADR-0134 §D13).
#
# THE DIVERGENCE THIS CLOSES. Two sites decided "does this issue already have a SPEC" with two
# different predicates. `autopilot` Phase P step 3 (`prep-row-select.sh`) tested the EXACT path
# `docs/specs/<map-slug>.spec.md`. `project-conductor` globbed `docs/specs/<issue>-*.spec.md` and
# took `head -1`. They disagreed whenever a SPEC existed for an issue under a slug other than the
# map's — measured live: ADR-0134's own Correction 1, where the map slug for issue #365 was
# `365-a-nightly-run-cannot-be-scoped-to-a` while a `365-*` glob matched an already-existing file
# under a different name. Generating a fresh SPEC under the map slug when a differently-named one
# already covers the issue would leave two candidates on disk and an arbitrary `head -1` downstream
# — ADR-0069/ADR-0086's criterion applies (two copies answering the SAME question is the defect):
# one predicate, loaded by both sites, rather than two copies kept in sync by inspection.
#
# WHY THE GLOB, NOT THE EXACT SLUG, IS AUTHORITATIVE. A chain archives its SPEC under its OWN
# topic slug (ADR-0106), which need not match the issue-map's slug field for the same issue number
# — the map is generated once and never regenerated (ADR-0134 §D13 A2), so it can name a slug that
# was never actually used to archive anything. The issue number is the one identifier both an
# issue-map row and an archived SPEC agree on unconditionally; the glob is coverage-detection, not
# a naming rule — a caller that still needs a path to generate a NEW spec under uses the map slug
# for that, unaffected by this script.
#
# CONTRACT. A REPORTER (rule 5): always exits 0. Prints the resolved path on stdout if a SPEC
# covering this issue exists, prints nothing if none does. Resolution is deterministic — sorted,
# lexicographically first match — never the OS's arbitrary directory-entry order, which is exactly
# what made the pre-#414 `head -1` at the project-conductor site arbitrary when two candidates
# existed.
#
# Usage: spec-coverage-lookup.sh <docs/specs-dir> <issue-number>
# stdout: the resolved path, or nothing.
# Exit: always 0. Bad invocation (wrong arg count) is the one exception -> exit 2.
set -u

SPECDIR="${1:-}"
ISSUE="${2:-}"
if [ -z "$SPECDIR" ] || [ -z "$ISSUE" ]; then
  printf 'spec-coverage-lookup.sh: usage: spec-coverage-lookup.sh <docs/specs-dir> <issue-number>\n' >&2
  exit 2
fi

_found=$(ls "$SPECDIR/$ISSUE"-*.spec.md 2>/dev/null | sort | head -1)
printf '%s' "$_found"
exit 0
