# SPEC — Scope guards: autopilot CWD check, conductor glob, nightly check 6

Source: GitHub issue #34

## Objectives
1. Fix the inverted, non-slash-anchored autopilot-build check-1 scope guard (audit finding 2.5, P2).
2. Anchor the project-conductor manifest lookup so a feature slug contained in another slug cannot bind to the wrong manifest (finding 3.10).
3. Give nightly-autopilot pre-flight check 6 a concrete command and an explicit empty-set rule for the Phase P flow (finding 3.11).

## Scope
In (all under `staging/plugin/skills/`):
- `autopilot-build/SKILL.md:60`: check 1 is inverted relative to ADR-0020 line 80 and its own line 34, and the prefix strip is not slash-anchored. Verified behavior today: parent CWD (allowed by the ADR) aborts; child CWD (forbidden) passes; sibling `myproj-backup` passes. Rewrite: pass iff CWD equals project_root, or project_root is strictly under CWD with a slash-anchored prefix comparison; quote the pattern side. nightly-autopilot inherits by reference.
- `project-conductor/SKILL.md:59` (also 164, 247): the glob `*<topic-slug>*.manifest.yml` matches by substring (export vs export-csv binds wrong, can auto-mark a feature completed without running). Anchor the glob to the manifest naming convention and verify the manifest's topic field matches the derived slug before acting on current_step. Apply at all three call sites.
- `nightly-autopilot/SKILL.md:103`: pre-flight check 6 (hook_verified known) has no command and no empty-set rule; in the ADR-0023 Phase P flow no manifests exist yet at pre-flight time. Give it runnable bash and an explicit rule: with zero manifests, consult the global smoke-test record written by hook-verify-workflow.sh (ADR-0016 result is global per CC version) and abort only if that record is absent.

Out:
- Any file under `~/.claude`.
- hook-verify-workflow.sh internals (issue #33).

## Stack
Markdown SKILL.md instruction text with embedded bash; harness tests in docs-ci.

## Architecture
Three SKILL.md files; a harness test driving the check-1 logic and the conductor slug-binding logic against fixtures.

## Data model
Manifest naming convention `<...slug...>.manifest.yml` plus the manifest `topic` field as the binding key.

## API / Interfaces
Check-1 contract: pass iff CWD == project_root, or project_root strictly under CWD (slash-anchored). Check-6 contract: manifests carry hook_verified true/false; zero manifests → global smoke-test record decides.

## UI flows
None.

## Edge cases
- Parent CWD with project_root beneath it: PASS (ADR-0020 allows).
- Child CWD (project_root above CWD): ABORT.
- Sibling directory sharing a name prefix (`myproj` vs `myproj-backup`): ABORT.
- Feature slug `export` with an `export-csv` manifest present: must not bind.
- Phase P pre-flight with zero manifests: check 6 falls back to the global smoke-test record; abort only if absent.
> **Deviation note (ADR-0030 §3.3):** the "global smoke-test record" named in this spec does not
> exist anywhere in the system (confirmed by ADR-0029) and was deliberately NOT invented. The
> shipped check 6 uses a roadmap-wide hook_verified validity check with a documented non-blocking
> zero-manifest pass: manifest-init defaults hook_verified to false, which already guarantees the
> safe agent-batch dispatch fallback. See ADR-0030 for the alternatives comparison.


## Success criteria
- [x] Harness test drives the check-1 logic with the three verified scenarios (parent passes, child aborts, sibling aborts)
- [x] Harness test: an export feature does not bind to an export-csv manifest
- [x] Check 6 has runnable bash and a documented zero-manifest branch
- [x] No file under `~/.claude` modified
