# Documentation and process conventions

- **Rule 14 in practice:** a historical ADR's body is never edited in place once it has SHIPPED —
  amend forward with a dated `## Correction`. An **in-flight** ADR at an open gate is the opposite:
  edit it in place, since a correction block on an unapproved ADR presents the operator two designs
  with no statement of which is being approved.
- Only `docs/vibe-coding-system.md`'s §15 installation checklist and §8.6's "Deployed custom skills"
  table make live-status claims; §8.3 (per-skill catalog) and §4 (illustrative CLAUDE.md template)
  are historical/illustrative and do not reflect current state.
- ADR numbers are allocated **per branch, not per repo** — check `git log --all` or any known
  in-flight branch before picking the next NNN, not just `ls docs/architecture/`.
- `docs/superpowers/plans/*.md` and `docs/specs/<N>-*.spec.md` pair reliably by issue-number
  prefix. Manifests are a weaker corpus source: many still point `artifacts.spec` at the mutable
  root `SPEC.md` slot (pre-ADR-0106) rather than the archived path.
- Cite a section/fixture name in cross-references, never a line number — `docs/` is outside the
  line-number-ban harness's population, but numbers rot fastest in files being actively corrected
  regardless of whether anything enforces it.
- When a brief names an exact closed count of violation sites, treat it as settled and
  disclose-don't-fix any additional candidate found. Open-ended phrasing ("reconcile all counts")
  licenses fixing the whole adjacent self-contradictory block. The instruction's own phrasing
  determines which discipline applies — read it carefully before choosing.
- Manifest naming: `docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml`; the `topic:` field IS the
  kebab slug (`topic_full_title:` is the display title) — the binding key for lookups.
- `manifest-set-gate.sh`/`manifest-set-flag.sh` both require their target field to already exist
  (grep-gated) — neither can create a new field. Reuse a pre-registered field or treat adding one
  explicitly as a schema change.
- Staging vendoring must never create a second source of truth: before a "copy the whole directory"
  pass, check whether a file inside already has an existing PAIRS entry at a different staging path
  and exclude it.
- `docs/RUNBOOK.md` is a second, independent deploy mechanism from `sync-to-claude.sh`/PAIRS: bulk,
  HITL-gated, glob-based full disaster-recovery copy. Check whether RUNBOOK's bulk copy already
  reaches a file before assuming PAIRS is the only path to it.
