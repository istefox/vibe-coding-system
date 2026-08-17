#!/usr/bin/env bash
# concept-to-code: spec-archive.sh — bash 3.2-clean
#
# Archive the OUTGOING root SPEC.md before a greenfield chain's interview overwrites it
# (issue #228, ADR-0096).
#
# Root SPEC.md is a single mutable slot every chain writes. `gate0-detect.sh` already detects that
# the slot holds a different topic — it reports `spec_topic_match=false` and flips the chain to
# greenfield, which "disowns" the SPEC for ROUTING purposes only. The file stays exactly where
# Step 1 is about to write. The detection existed, fired, and protected nothing.
#
# Usage: spec-archive.sh <project-root> <outgoing-topic-slug>
#   <outgoing-topic-slug> is `spec_topic_slug` from gate0-detect.sh. This script deliberately does
#   NOT re-derive it from the SPEC's marker: two extractors that disagree would archive under a
#   name the detector never saw, or skip a SPEC the detector flagged. One extractor, one answer
#   (ADR-0086's criterion — extract when two copies giving different answers would be a defect).
#
# stdout (one line):
#   NOSPEC              no root SPEC.md — nothing to protect
#   ALREADY <path>      byte-identical content is already archived, under ANY name
#   ARCHIVED <path>     copied to the archive
#   COLLISION <path>    the destination exists with different content — refused
#
# Exit: 0 ran (NOSPEC | ALREADY | ARCHIVED) | 1 refused (COLLISION) | 3 did NOT run
#
# The 3 matters: a caller cannot otherwise tell "no SPEC to archive" — the common, legitimate case —
# from "this script could not run at all", and treating the second as the first is how a guard comes
# to protect nothing while looking green.
#
# IT COPIES, IT NEVER MOVES. Two reasons, and both are load-bearing: nothing is deleted without a
# human saying so, and the incoming interview overwrites the root slot anyway, so a move buys
# nothing and risks losing the file if the interview then fails.
set -u

if [ "$#" -ne 2 ]; then
  echo "usage: spec-archive.sh <project-root> <outgoing-topic-slug>" >&2
  exit 3
fi

root="$1"
slug="$2"

[ -d "$root" ] || { echo "spec-archive: not a directory: $root" >&2; exit 3; }

# THE SHAPE GUARD STAYS ABOVE THE EXISTENCE CHECK, and the two are deliberately no longer one
# `case` (issue #455). A slug carrying a path, a leading dot or a leading dash is a malformed CALL,
# and a malformed call is malformed whether or not the root happens to hold a SPEC.md. Sinking it
# below the check would turn `spec-archive.sh <empty-root> ../../etc/passwd` into a silent 0.
case "$slug" in
  */*|.*|-*)
    echo "spec-archive: refusing a slug that is not a bare name: $slug" >&2
    exit 3 ;;
esac

spec="$root/SPEC.md"
[ -f "$spec" ] || { echo "NOSPEC"; exit 0; }

# ONLY NOW is an empty-or-`unknown` slug a defect, and that ordering is the whole of issue #455.
#
# `unknown` reaches this script from TWO producers, and until #455 the comment here named only one
# of them. `gate0-detect.sh` emits `spec_topic_slug=unknown` both for a SPEC.md with no marker —
# which routes to brownfield and never gets here — AND for a root with no SPEC.md at all, which
# routes to GREENFIELD and is precisely what Step 1's fence runs on. So the fence's documented
# "no-op on the genuinely-empty one" was a HALT: this guard refused before anything had looked for
# the file, and the caller's contract on exit 3 is to stop the chain. That is the bootstrap path,
# the one case this repository never exercises on itself because its root slot is never empty.
#
# The check above settles the empty root as NOSPEC. What survives to here is a SPEC.md that EXISTS
# with no slug to name its archive — a genuinely confused caller, refused as before.
case "$slug" in
  ""|unknown)
    echo "spec-archive: outgoing slug is empty or unknown — refusing to name an archive" >&2
    exit 3 ;;
esac

archive_dir="$root/docs/specs"

# Already archived? Compare by CONTENT, never by filename.
#
# Measured on this repository before the check was written: 41 manifests, and only 3 of their topic
# slugs name an existing `docs/specs/<slug>.spec.md`. The archive names come from the SPEC's own
# title, while a topic slug is truncated to 40 characters — `100-secrets-and-dependency-gate-content`
# against `100-secrets-and-dependency-gate-content-scan.spec.md`. A by-name check would miss 38
# existing archives and cheerfully write a duplicate beside each.
if [ -d "$archive_dir" ]; then
  for f in "$archive_dir"/*.spec.md; do
    [ -f "$f" ] || continue
    if cmp -s "$spec" "$f"; then
      echo "ALREADY $f"
      exit 0
    fi
  done
fi

dest="$archive_dir/$slug.spec.md"

# Nothing above matched by content, so an existing destination holds DIFFERENT content. Overwriting
# it would be issue #228 reproduced one level down, in the directory that exists to prevent it.
if [ -e "$dest" ]; then
  echo "COLLISION $dest"
  exit 1
fi

mkdir -p "$archive_dir" || { echo "spec-archive: cannot create $archive_dir" >&2; exit 3; }
cp "$spec" "$dest"      || { echo "spec-archive: cannot write $dest" >&2; exit 3; }

echo "ARCHIVED $dest"
exit 0
