# Memory index

One line per topic. The durable facts live in the linked file, not here — this index stays under
the 200-line/25KB injection cap; the topic files do not.

Migrated from the ADR-0012 mediated store (`memory/agent-notes/architect.md`, 229 lines / 52KB,
harvested 2026-07-11 → 2026-08-23) on 2026-08-31 as part of VCS-056/ADR-0183. That store is left
in place as the historical record, not deleted.

- [plant-check.sh mechanics](topics/plant-check-mechanics.md) — plant-id prefix matching, sandbox
  scope (staging/+docs/ only), the env-configures/flags-select-mode idiom
- [spec-coverage.sh, diff-budget-check.sh, plan-tasks.sh](topics/spec-coverage-and-plan-tools.md) —
  requirement-id citation traps, the STALE-WAIVER block, budget-line parsing, re-derive-don't-cite,
  why RS7/RS8a go red the moment a plan file lands
- [Harness blast radius](topics/harness-blast-radius.md) — deleting a staged file breaks more than a
  SPEC lists: frozen exact baselines, negative-shaped assertions, population floors, orphaned plants
- [Write scope and command scope](topics/write-and-command-scope.md) — the three allowed write
  roots (VCS-056 added agent-memory), what `agent-command-scope.sh` actually blocks, frontmatter
  fields that silently don't do what they look like they do
- [CI wiring and shell portability](topics/ci-wiring-and-shell-portability.md) —
  `docs-ci.yml`'s named list vs the local glob, markdownlint scope, zsh-vs-bash divergences a
  bash-run test harness cannot see, and why THIS memory store is itself lint- and link-gated
- [Documentation and process conventions](topics/documentation-and-process-conventions.md) —
  rule 14 in practice, ADR numbering, manifest/SPEC pairing, when to disclose vs when to fix
