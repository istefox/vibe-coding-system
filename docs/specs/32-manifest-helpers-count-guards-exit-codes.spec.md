# SPEC — Manifest helpers: count guards, exit codes, YAML escaping

Source: GitHub issue #32

## Objectives
1. Fix the `grep -c ... || echo 0` two-line-value bug that silently skips manifest-validate invariant 9 (audit finding 3.3).
2. Make `manifest-set-artifact.sh` and `manifest-set-gate.sh` fail loud on write failure, mirroring `manifest-set-flag.sh` (findings 3.4).
3. Escape YAML-breaking characters in `manifest-init.sh` titles, fix SKILL.md PATH-RULE violations, and reconcile the transition-pair counts (findings 3.5–3.7).

## Scope
In (`staging/plugin/skills/concept-to-code/scripts/` + SKILL.md, vendored by issue #28):
- `manifest-validate.sh:130`: `grep -c ... || echo 0` yields `0\n0` when no gate lines exist (grep -c prints 0 AND exits 1); the integer comparison errors and invariant 9 is silently skipped. Drop the `|| echo 0`, guard the empty case explicitly.
- `manifest-set-artifact.sh:45`, `manifest-set-gate.sh:55`: exit 0 unconditionally even when the awk/mv write fails. Mirror set-flag's handling: exit 4 plus mktemp cleanup trap.
- `manifest-init.sh:61`: `topic_full_title` echoed unescaped inside double quotes; a title containing `"` produces YAML that crashes autopilot-build's yaml.safe_load pre-flight. Escape double quotes and backslashes before writing.
- SKILL.md lines 531, 533, 1146, 121, 1323: bare/relative script calls violating the file's own PATH RULE; use the absolute script prefix at all five sites.
- SKILL.md lines 213, 229 and manifest-transition.sh line 50: pair counts disagree three ways (44, 51, 16) while the script encodes 48; the section-3 hybrid list omits the two gate_h1c pairs. Reconcile all counts to the actual 48 and complete the hybrid enumeration.

Out:
- Any file under `~/.claude`.
- SKILL.md gate-logic changes (issue #31).

## Stack
Bash 3.2-compatible scripts, Markdown SKILL.md, harness tests in docs-ci.

## Architecture
Four scripts (`manifest-validate.sh`, `manifest-set-artifact.sh`, `manifest-set-gate.sh`, `manifest-init.sh`), `manifest-transition.sh` count comment, and five SKILL.md call sites, all under `staging/plugin/skills/concept-to-code/`.

## Data model
Manifest YAML: titles with double quotes/backslashes must serialize to valid YAML.

## API / Interfaces
Exit-code contract: set-artifact/set-gate exit 4 on write failure (matching set-flag).

## UI flows
None.

## Edge cases
- Manifest with a `hitl_gates` key but zero gate lines: invariant 9 must FAIL validation, not be skipped.
- Unwritable manifest: set-artifact/set-gate exit 4, not 0; temp files cleaned up.
- Title containing `"` or `\`: resulting manifest must parse with yaml.safe_load.

## Success criteria
- [x] Harness test: a manifest with a hitl_gates key but zero gate lines FAILS validation (invariant 9 fires)
- [x] Harness test: set-artifact against an unwritable manifest exits 4, not 0
- [x] Harness test: init with a title containing a double quote produces a manifest that yaml.safe_load parses
- [x] All scripts stay bash 3.2 clean
- [x] No file under `~/.claude` modified
