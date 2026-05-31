# ADR-0005 — Vibe-status skill

**Status:** Accepted  
**Date:** 2026-05-20  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:**
- `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md`
- `docs/superpowers/plans/2026-05-20-vibe-status-skill.md`
- `~/.claude/skills/concept-to-code/` (pattern skill markdown + scripts as reference)
- `~/.claude/skills/refactor-snapshot/` (recent skill pattern)
- Memory `feedback_bash32-constraint.md`

---

## 1. Context

The vibe-coding system (`docs/vibe-coding-system.md`) is now composed of 8 sub-agents + ~12
skills + 4 hooks + 3 ADRs (0001-0003) + a persistent memory layer. **The current state of the
system is not aggregately inspectable**: to know "is everything healthy?" today requires manually:

1. `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` -> PASS=47
2. `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` -> PASS=10
3. `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` -> PASS=11
4. `ls docs/architecture/` (for ADR and status)
5. `ls docs/manifests/` (for in-flight concept-to-code manifest, if present)
6. `cat ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
7. `cat .triage-fix-last.json` (if present — output of last review-triage-fix)
8. Verify `~/.claude/settings.json` for configured hooks

**8 separate lookup points.** System audit 2026-05-20: the only "skill aggregator" does not
exist. Measurable operational friction (3-5 min for a complete manual audit).

**Direction:** introduce **markdown skill `vibe-status`** callable by the orchestrator
as `/skill vibe-status`, producing a single Markdown report with:

- State of N harnesses (PASS/FAIL count, duration)
- In-flight manifests (`docs/manifests/` if present in cwd)
- Existing ADRs and their status (parsing first line `**Status:**`)
- Installed custom skills (ls `~/.claude/skills/`)
- Hooks configured in `~/.claude/settings.json`
- Recent review-triage-fix cycle (`.triage-fix-last.json` if present)
- Active memory entries (head of MEMORY.md)

Report printed to stdout, well-formatted Markdown for chat rendering, <10s typical.

### Inherited constraints

- **Anchor preservation `review-triage-fix`:** PASS=47 must remain >= 47.
- **Bash 3.2.57 compat** for aggregator script.
- **Read-only:** skill does NOT modify any system file. Read only.
- **Performance target:** <10s typical case.
- **No HITL in design phase.**
- **NON-git repo:** no commit step.

### Explicit assumptions (not empirically verified)

- **The `/skill vibe-status` invocation from orchestrator loads `SKILL.md` and executes the
  steps described** (aligned with the pattern of `concept-to-code` and `refactor-snapshot`).
  Verified for the 2 existing skills.
- **The skill can execute bash scripts (`scripts/aggregate.sh`) as part of its steps**
  (pattern of `concept-to-code/scripts/`).
- **The typical case has <=5 active harnesses** (today 3, growth to 5-6 expected in 2026 Q3).
  Performance budget 10s = 2s per harness x 5 harnesses + 0-fluff overhead.
- **The skill is cwd-sensitive:** the invoker is in `$PWD = current project`. Global discovery
  of `~/.claude/skills/*/tests/` + local discovery of `./docs/manifests/`,
  `./docs/architecture/`, `./.triage-fix-last.json` if present.

---

## 2. Decision

Introduce the skill **`vibe-status`** in `~/.claude/skills/vibe-status/` with the
standard structure (SKILL.md + scripts + tests), callable as `/skill vibe-status`.
Produces Markdown report to stdout in <10s typical.

### 2.1 Answers to the 6 architectural questions

#### Q1 — Form: markdown skill vs standalone bash

**Markdown skill in `~/.claude/skills/vibe-status/SKILL.md` with `scripts/aggregate.sh`
helper.**

Rationale:
- Consistent with `concept-to-code`, `refactor-snapshot`, `review-triage-fix` (established
  pattern).
- The `/skill vibe-status` invocation is discoverable in CLI tab-completion.
- The SKILL.md can provide interpretive context to the LLM (e.g. "if 1 harness fails,
  flag MAJOR; if all pass, declare HEALTHY") beyond the raw output of the script.
- `~/.claude/bin/vibe-status` standalone bash would be an alternative but breaks the
  convention (never used pattern in the current system, not discoverable by the orchestrator
  without separate documentation).

**Hybrid pattern:** SKILL.md orchestrates; `scripts/aggregate.sh` does the heavy lifting
(harness invoke + manifest scan + ADR parse) producing raw Markdown. SKILL.md can add
a semantic layer on top (HEALTHY/DEGRADED/CRITICAL header) post-hoc if the LLM chooses
to interpret.

#### Q2 — Discovery of files to aggregate

**Hybrid: auto-discovery with convention + optional override via manifest.**

Default behavior (no manifest):
- **Harnesses:** glob `~/.claude/skills/*/tests/run-tests.sh` (3.2-portable via `for f in
  ~/.claude/skills/*/tests/run-tests.sh; do ... done`).
- **ADRs:** glob `<cwd>/docs/architecture/ADR-*.md` (cwd-local).
- **Manifests:** glob `<cwd>/docs/manifests/*.yaml` if directory exists.
- **Triage state:** `<cwd>/.triage-fix-last.json` if file exists.
- **Hooks:** parse `~/.claude/settings.json` with jq.
- **Memory:** head of `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md` if it exists.

Optional override via `<cwd>/.claude/vibe-status.yaml` (if present):
```yaml
harness:
  - path: ~/.claude/skills/custom/tests/run-tests.sh
    timeout: 30
  - skip: ~/.claude/skills/swift-vibe/tests/run-tests.sh
adr_dir: docs/architecture
manifests_dir: docs/manifests
```

Trade-off: hardcoded list in SKILL.md would be simpler (3 harnesses today) but does not
scale (a new harness requires editing SKILL.md). Auto-discovery is write-once, self-updating.

#### Q3 — Cwd sensitivity: global vs local

**Hybrid: global (always) + local (if paths exist in cwd).**

Behavior:
- **Always reads (global):**
  - `~/.claude/skills/*/tests/run-tests.sh` (harnesses)
  - `~/.claude/skills/*/SKILL.md` (skill list)
  - `~/.claude/settings.json` (hook config)
  - `~/.claude/agents/*.md` (agent list)
- **Conditionally reads (local):**
  - `<cwd>/docs/architecture/ADR-*.md` if directory exists — otherwise ADR section of the
    report shows `(no project ADR directory)`.
  - `<cwd>/docs/manifests/*.yaml` if directory exists — otherwise manifest section shows
    `(no in-flight manifests)`.
  - `<cwd>/.triage-fix-last.json` if file exists — otherwise `(no recent triage cycle)`.
  - `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md` if file exists.

If `$PWD = ~` (home, no project context), the local section degrades to "(no project
context)" without erroring.

#### Q4 — Performance + parallel/cache

**Harness parallelization with per-harness timeout + optional cache.**

Default v1.0:
- Harnesses executed **in parallel** via background subshell + wait (3.2-portable):
  ```bash
  for h in "$@"; do
    ( bash "$h" >"$TMP/$(basename $(dirname $(dirname $h)))" 2>&1; echo $? > "$TMP/rc.$$" ) &
  done
  wait
  ```
- **Per-harness timeout:** 8s default, configurable via env `VIBE_STATUS_HARNESS_TIMEOUT`.
- If >timeout: skip + flag `TIMEOUT` in report (does not block other sections).
- **No cache v1.0.** Premature: 3 harnesses in parallel in 8s = walltime <=8s, under budget.
  Cache requires invalidation (file mtime? sha?), deferred to v1.1 if pilot metrics show
  recurring slowness.

Skip-flag opt-in: `--skip-harness` produces report without executing harnesses (metadata-only
scan, <1s).

#### Q5 — Output format

**Default: Markdown to stdout. Flag `--json` for JSON. Flag `--plain` for plain text.**

Default (Markdown):

```markdown
# Vibe-Coding System Status — 2026-05-20 14:32

## Health: HEALTHY

## Harness (3/3 passing)
| Skill | PASS | FAIL | Duration | Status |
|---|---|---|---|---|
| review-triage-fix | 47 | 0 | 2.1s | OK |
| concept-to-code | 10 | 0 | 1.4s | OK |
| refactor-snapshot | 11 | 0 | 1.9s | OK |

## ADR (3 total)
- ADR-0001 — Coder pre-flight pattern classifier — Accepted 2026-05-20
- ADR-0002 — Refactor snapshot harness — Accepted 2026-05-20
- ADR-0003 — Concept-to-code chain — Accepted 2026-05-20

## In-flight manifests
(none)

## Recent triage cycle
2026-05-20 11:05 — review-triage-fix v1.2 — PASS

## Hooks (4 configured)
- stop-gate.sh (Stop)
- approve-test-cmd.sh (utility)
- migrate-trust-paths.sh (utility)
- backup-before-deploy.sh (PreToolUse)

## Memory entries
- 4 project entries (1 RESOLVED, 1 SUPERSEDED)
- 3 feedback entries (all active)
```

The `--json` flag emits the same content as structured for programmatic consumption
(future skill chaining).

Output exclusively to stdout — no file written (read-only constraint).

#### Q6 — Failure mode

**Skip-and-flag, never block entire report.**

Cases:
- **1 harness timeout:** harness section shows `TIMEOUT` row; other harnesses complete;
  overall status `DEGRADED` (not `CRITICAL`).
- **1 harness FAIL:** shows PASS/FAIL count; overall status `DEGRADED`.
- **1 harness crash (exit 127, file not found, etc.):** harness section shows `ERROR`
  row with tail of stderr (last 80 chars); overall status `DEGRADED`.
- **`~/.claude/settings.json` malformed (jq parse error):** hook section shows
  `(unable to parse settings.json)`; overall status `DEGRADED`.
- **`<cwd>/docs/architecture/` does not exist:** ADR section `(no project ADR directory)`;
  overall status unchanged (local, does not penalize).

Overall status legend:
- **HEALTHY:** all harnesses PASS, no errors in metadata.
- **DEGRADED:** >=1 harness FAIL/TIMEOUT/ERROR or metadata parse error.
- **CRITICAL:** >=2 harnesses FAIL simultaneously or all harnesses ERROR.

Status legend printed in footer of report for clarity.

### 2.2 Skill architecture

```
~/.claude/skills/vibe-status/
├── SKILL.md                          # orchestrator markdown, ~80 lines
├── scripts/
│   ├── aggregate.sh                  # main entry, 3.2-clean, ~200 lines
│   ├── harness-runner.sh             # invoke single harness with timeout
│   └── render-markdown.sh            # format output
└── tests/
    └── run-tests.sh                  # anchor + smoke test, ~50 anchor target

# Structural anchor in review-triage-fix harness:
~/.claude/skills/review-triage-fix/tests/run-tests.sh  # +1 anchor: vibe-status skill presence
```

### 2.3 Coexistence with `review-triage-fix` harness

The `review-triage-fix` harness (PASS=47) acquires **+1 anchor** that verifies the presence
of the file `~/.claude/skills/vibe-status/SKILL.md` and the literal `Vibe-Coding System Status`
in the SKILL.md. Trade-off: ties review-triage-fix to a fourth file (after its own `SKILL.md`,
`coder.md` from ADR-0001, `settings.json` from ADR-0004), but the principle "review-triage-fix
has authority over the quality of the stack" extends consistently.

**Harness PASS=47 -> PASS=48** (with ADR-0004 = PASS=49 cumulative if both deployed;
each independently contributes +1).

### 2.4 Does the skill have its own harness?

**Yes, dedicated in `~/.claude/skills/vibe-status/tests/run-tests.sh`.** Pattern of
`concept-to-code/tests` and `refactor-snapshot/tests`. Anchors:
- presence of SKILL.md
- presence of scripts/aggregate.sh executable
- smoke test: invoke aggregate.sh on mock tmp env produces well-formed Markdown
  (head has `# Vibe-Coding System Status`)
- harness discovery: glob `~/.claude/skills/*/tests/run-tests.sh` returns >=3 files
- ADR parsing: parse of a fixture ADR extracts title and status
- timeout: fixture harness that sleeps 30s is killed in 8s

Target PASS=8-10 anchors in its own harness. That harness becomes the 4th in
auto-discovery of `vibe-status` itself (self-referential, idempotent).

### 2.5 Language

SKILL.md in English (system contract). Bash scripts with comments in English. Reason field
and logs in Italian (user-facing). Spec, plan, memory, ADR in Italian. Aligned with
global rule.

---

## 3. Alternatives considered

### 3.1 Form: skill vs standalone bash (Q1)

**a) Markdown skill + scripts (CHOSEN).** Consistent with `concept-to-code`, `refactor-snapshot`.
Discoverable, contextualizable by the LLM, follows convention.

**b) Standalone bash `~/.claude/bin/vibe-status`** — *Rejected*. Never used pattern, would
duplicate directory structure. Not discoverable without alias or external doc. Does not allow
the LLM to interpret the output (e.g. "the system is DEGRADED because..."), only a raw dump.

**c) Dedicated sub-agent `vibe-monitor`** — *Rejected*. 8 sub-agents already cover the
spectrum; adding a 9th for status reporting is overkill (sub-agent = role with complex system
prompt, a skill aggregator suffices here).

### 3.2 Discovery (Q2)

**a) Auto-discovery + optional manifest override (CHOSEN).** Self-updating scaling; override
covers edge cases (internal test skills, experimental harnesses to skip).

**b) Hardcoded list in SKILL.md** — *Rejected*. Does not scale. A new harness requires
editing SKILL.md. Stale-by-design.

**c) Mandatory hardcoded manifest** — *Rejected*. Forces every project to maintain a config
file. Disproportionate friction for the benefit (default works for 95% of cases).

### 3.3 Cwd sensitivity (Q3)

**a) Hybrid global + local (CHOSEN).** Global for `~/.claude/` stack, local for project
context. Degrades gracefully if project context is missing.

**b) Global only** — *Rejected*. Loses ADR/manifest/triage of the current project, reduces
utility to 50%.

**c) Local only** — *Rejected*. Loses global harnesses/hooks/skills, reduces utility to 30%.

### 3.4 Performance / parallel (Q4)

**a) Parallel + per-harness timeout, no cache v1.0 (CHOSEN).** 8s timeout x 3-5 harnesses
in parallel = walltime <=8s. Under budget. Cache deferred.

**b) Sequential** — *Rejected*. 3-5 harnesses x 2-5s = 10-25s walltime. Over budget.

**c) TTL 60s cache** — *Rejected v1.0*. Requires storage in `~/.claude/state/vibe-status/`,
invalidation logic (file mtime check). Premature: parallel alone is sufficient.
Considerable v1.1 if metrics show recurring slowness.

### 3.5 Output format (Q5)

**a) Markdown default + `--json`/`--plain` flags (CHOSEN).** Markdown is the native rendering
of Claude Code chat, JSON is a hatch for future programmatic chaining (e.g. future skill
`vibe-status-watch` that parses JSON).

**b) Plain text default** — *Rejected*. Loses table formatting, harder to scan.

**c) JSON default** — *Rejected*. Not human-readable without tooling. The primary user
is Stefano in chat, not another tool.

### 3.6 Failure mode (Q6)

**a) Skip-and-flag, never block entire (CHOSEN).** Resilience: 1 broken harness does not
obscure other info.

**b) Block entire report on first failure** — *Rejected*. Anti-pattern: the status skill
that fails to render state is bad UX. If the skill cannot report, utility is zero.

**c) Retry on timeout** — *Rejected v1.0*. Adds complexity without clear benefit. A harness
that times out once probably times out twice. Defer.

---

## 4. Consequences

### 4.1 Positive

- **Single command for complete system audit.** From 8 manual lookups to 1 invocation.
  Time: 3-5 min -> <10s.
- **Self-updating via auto-discovery.** A new harness/skill is automatically included
  without editing config.
- **Read-only.** Zero risk of side effects on system files.
- **Consistent with convention.** Markdown skill + scripts pattern already established.
- **Programmatic-friendly via `--json`.** Future automation skills (e.g. weekly health check)
  can parse the output.
- **Anchor preserved** (PASS=47 -> PASS=48 for skill existence).
- **Bash 3.2-clean** by construction (script follows `stop-gate.sh` style).

### 4.2 Negative

- **Walltime up to 8s + overhead** under nominal load. Not instant. Mitigated by
  `--skip-harness` for quick metadata-only view (<1s).
- **Dependency on harness PASS count format** (parsing summary `PASS=N FAIL=N`). Harness
  format change breaks the parser. Mitigation: tolerant regex (`grep -E
  'PASS=[0-9]+'`), fail-graceful with `?` if no match.
- **Cwd-sensitive not always intuitive.** Stefano at `~` sees less info than at
  `~/Developer/vibe-coding-system`. Documented in SKILL.md header.
- **Settings.json parsing fragile on manual edits.** If JSON malformed (trailing comma,
  etc.), hook section is degraded. Mitigated by fail-graceful (see §2.1 Q6).
- **Coupling settings.json + review-triage-fix harness.** New anchor entry ties the harness
  to a 4th file (after SKILL.md, coder.md, future settings.json from ADR-0004). Future
  review-triage-fix refactor requires anchor update.

### 4.3 Neutral

- The current system works without the skill. It is purely additive.
- Memory `feedback_micropiano-refactor-cleanup` remains RESOLVED. No interaction.
- The orchestrator does not change: calls `/skill vibe-status` when it wants status,
  ignores otherwise.

### 4.4 Open questions (validation pending)

- **Real adoption:** will Stefano use `/skill vibe-status` regularly or will it remain
  unused? Validatable in 2 weeks of organic use. If unused, signal that the pre-existing
  friction was not actually high.
- **Performance under load.** 5+ harnesses with long session jsonl: respects the <10s
  budget? Measurable via plan task benchmark.
- **Parsing robustness on manually edited `~/.claude/settings.json`.** Stefano occasionally
  edits settings.json by hand; parser resilience verifiable only in use.

---

## 5. References

- `~/.claude/skills/concept-to-code/` (skill + scripts pattern)
- `~/.claude/skills/refactor-snapshot/` (recent pattern with harness)
- `~/.claude/skills/review-triage-fix/` (skill authoritative over stack quality)
- `~/.claude/hooks/stop-gate.sh` (robust bash 3.2-clean pattern)
- `docs/vibe-coding-system.md` sec. 8 (skill stack), sec. 3 (sub-agent list)
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (recent markdown skill pattern)
- Memory `feedback_bash32-constraint.md`
