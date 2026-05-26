# Vibe-status skill — Design spec

**Stato:** implementato — 2026-05-20 (harness PASS=49 + dedicated PASS=9; adozione organica da osservare)
**Data:** 2026-05-20
**ADR:** `docs/architecture/ADR-0005-vibe-status-skill.md` (Proposed)
**Plan:** `docs/superpowers/plans/2026-05-20-vibe-status-skill.md` (TDD, 7 task)

---

## 1. Problem statement

Audit 2026-05-20 del sistema vibe-coding: per sapere "è tutto sano?" servono 8 lookup
manuali separati (3 harness runs + 4 directory listings + 1 file cat). Tempo: 3-5 min.
Nessuno skill aggregator esiste.

Sistema in crescita: 8 sub-agent, 12 skill, 4+ hook, 3 ADR deployati 2026-05-20.
Estensioni future (ADR-0004 hook pattern-enforce, future skill) renderanno l'audit
manuale ancora più costoso.

---

## 2. Goal

Introdurre skill markdown `~/.claude/skills/vibe-status/` invocabile come
`/skill vibe-status`. Produce **singolo report Markdown su stdout** in <10s typical,
aggregando:

- Status dei harness skill auto-discovered (PASS/FAIL/duration)
- Lista ADR del project corrente (cwd) con status parsato
- Manifest in flight (concept-to-code) se directory `docs/manifests/` esiste
- Skill custom installati globalmente
- Hook configurati in `~/.claude/settings.json`
- Stato ultimo ciclo `review-triage-fix` (`.triage-fix-last.json` se presente)
- Memory entries (head di MEMORY.md della sessione)
- Overall health: HEALTHY | DEGRADED | CRITICAL

Read-only, parallel harness execution, fail-graceful per ogni section.

---

## 3. Decisioni di design (refinement post-ADR)

### 3.1 Struttura skill

```
~/.claude/skills/vibe-status/
├── SKILL.md                       # orchestrator markdown ~80 righe
├── scripts/
│   ├── aggregate.sh               # main entry, 3.2-clean ~200 righe
│   ├── harness-runner.sh          # invoke single harness con timeout
│   ├── parse-adr.sh               # extract status+title da ADR file
│   └── render-section.sh          # helper format markdown
└── tests/
    └── run-tests.sh               # harness anchor + smoke test
```

### 3.2 SKILL.md outline (inglese)

```markdown
---
name: vibe-status
description: Aggregate health report of the vibe-coding system. Runs harness, lists ADRs, manifests, skills, hooks, memory. Read-only, <10s typical.
---

# vibe-status

Single command to render the full health status of the vibe-coding system.

## When to invoke

- Before a complex multi-agent dispatch — verify system is HEALTHY.
- After a deploy — confirm harness regression is clean.
- Periodic check — discover skills/hooks added recently.

## Process

1. Run `scripts/aggregate.sh` with optional flags (`--json`, `--plain`, `--skip-harness`).
2. Render output as Markdown in chat.
3. Interpret overall status: HEALTHY (all green) | DEGRADED (≥1 issue) | CRITICAL (≥2 harness fails OR all harness errors).

## Flags

- `--json` → JSON output for programmatic consumption
- `--plain` → plain text (no markdown table)
- `--skip-harness` → metadata-only, <1s

## Defaults

- Harness timeout per-skill: 8s (env `VIBE_STATUS_HARNESS_TIMEOUT`)
- Window: cwd-aware (locale: ADR/manifest/triage; globale: harness/hook/skill)
```

### 3.3 aggregate.sh logic

Sezioni in ordine di esecuzione:

1. **Args parsing.** `--json`, `--plain`, `--skip-harness`. Default markdown.
2. **Globale section discovery.**
   ```bash
   # Harness glob
   for f in "$HOME"/.claude/skills/*/tests/run-tests.sh; do
     [ -f "$f" ] && HARNESSES="$HARNESSES $f"
   done
   ```
3. **Locale section discovery.** `[ -d "$PWD/docs/architecture" ]`, `[ -d "$PWD/docs/manifests" ]`, `[ -f "$PWD/.triage-fix-last.json" ]`.
4. **Harness parallel execution.** Background subshell + wait + per-harness file
   output:
   ```bash
   TMP=$(mktemp -d)
   for h in $HARNESSES; do
     name=$(basename "$(dirname "$(dirname "$h")")")
     ( bash "scripts/harness-runner.sh" "$h" "$VIBE_STATUS_HARNESS_TIMEOUT" >"$TMP/$name" 2>&1 ) &
   done
   wait
   ```
5. **Parse harness results.** Per ogni file in `$TMP`: extract `PASS=N`, `FAIL=N`,
   duration, status (OK | FAIL | TIMEOUT | ERROR).
6. **ADR parsing.** Per ogni `docs/architecture/ADR-*.md`:
   `grep -m1 '^# ADR-' file` → title, `grep -m1 '^\*\*Status:\*\*' file` → status.
7. **Manifest scan.** `ls docs/manifests/*.yaml 2>/dev/null` → count + list.
8. **Skill discovery.** `ls -d ~/.claude/skills/*/` → count + names.
9. **Hook parsing.** `jq -r '.hooks | keys[] as $k | "\($k): \(.[$k] | length)"' ~/.claude/settings.json`.
10. **Triage state.** Se `.triage-fix-last.json` esiste:
    `jq -r '.timestamp, .skill, .result' file`.
11. **Memory.** `head -20 ~/.claude/projects/<enc>/memory/MEMORY.md` se esiste.
12. **Overall status calc.** Logic in §3.5.
13. **Render.** Markdown table per harness, bullet list per altri. Footer status legend.

### 3.4 harness-runner.sh

Single harness invoker with timeout. Pattern da `stop-gate.sh` linee 77-88:

```bash
#!/bin/bash
H="$1"; TMO="$2"
START=$(date +%s)
if command -v timeout >/dev/null 2>&1; then
  timeout "$TMO" bash "$H" 2>&1
  RC=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$TMO" bash "$H" 2>&1
  RC=$?
else
  bash "$H" 2>&1 &
  P=$!
  ( sleep "$TMO"; kill -9 "$P" 2>/dev/null ) &
  W=$!
  wait "$P" 2>/dev/null; RC=$?
  kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
  [ "$RC" -eq 137 ] && RC=124
fi
END=$(date +%s)
DUR=$((END - START))
echo "RC=$RC DUR=${DUR}s"
```

Out parsato da aggregate.sh: `RC=0` → OK, `RC=124` → TIMEOUT, altro → ERROR.

### 3.5 Overall status logic

```
HARNESS_OK=count(status == OK)
HARNESS_TOTAL=count(all)
HARNESS_FAIL=count(status == FAIL)
HARNESS_ERROR=count(status == ERROR || status == TIMEOUT)

if HARNESS_OK == HARNESS_TOTAL && no metadata-error:
  STATUS=HEALTHY
elif HARNESS_FAIL >= 2 || HARNESS_ERROR == HARNESS_TOTAL:
  STATUS=CRITICAL
else:
  STATUS=DEGRADED
```

Footer del report stampa esplicitamente la legenda.

### 3.6 Output Markdown sample

```markdown
# Vibe-Coding System Status — 2026-05-20 14:32

## Health: HEALTHY

## Harness (3/3 passing)
| Skill | PASS | FAIL | Duration | Status |
|---|---|---|---|---|
| concept-to-code | 10 | 0 | 1.4s | OK |
| refactor-snapshot | 11 | 0 | 1.9s | OK |
| review-triage-fix | 47 | 0 | 2.1s | OK |

## ADR (3 total in docs/architecture/)
- ADR-0001 — Coder pre-flight pattern classifier — Accepted 2026-05-20
- ADR-0002 — Refactor snapshot harness — Accepted 2026-05-20
- ADR-0003 — Concept-to-code chain — Accepted 2026-05-20

## In-flight manifests (docs/manifests/)
(none)

## Recent triage cycle
2026-05-20 — review-triage-fix v1.2 — PASS=47

## Skill custom (12 installed)
adr-writer, claude-md-generator, code-review-checklist, concept-to-code,
fastapi-react-vibe, find-skills, interview-driver, project-bootstrap,
refactor-snapshot, review-triage-fix, swift-vibe, swiftui-pro

## Hooks (settings.json)
- PreToolUse: 3 entries
- PostToolUse: 1 entry
- Stop: 1 entry

## Memory (head)
4 project entries, 3 feedback entries (1 RESOLVED, 1 SUPERSEDED).

---
Legend: HEALTHY = all harness pass + no metadata error.
        DEGRADED = ≥1 harness FAIL/TIMEOUT/ERROR or metadata parse error.
        CRITICAL = ≥2 harness FAIL or all harness ERROR.
Generated in 6.4s.
```

### 3.7 Tests harness della skill

`~/.claude/skills/vibe-status/tests/run-tests.sh`. Cover:

1. **SKILL.md exists + has name field.**
2. **scripts/aggregate.sh exists + executable.**
3. **scripts/harness-runner.sh exists + executable.**
4. **Smoke test: aggregate.sh su mock env produce Markdown well-formed** — fixture
   tmp dir + 1 fake harness che echo `PASS=5 FAIL=0`; aggregate stdout contiene
   `# Vibe-Coding System Status` e `## Harness`.
5. **Skip-harness flag mode** — `aggregate.sh --skip-harness` non invoca harness, output
   ha sezione `## Harness` con `(skipped)` o equivalente.
6. **JSON flag output** — `--json` produce JSON parsabile, jq estrae `.health` e
   `.harness[]`.
7. **Harness timeout simulation** — fixture harness che sleep 30s viene killed in 2s
   (timeout test); aggregate riporta `TIMEOUT` status.
8. **Missing ADR directory degrades gracefully** — fixture cwd senza
   `docs/architecture/`: aggregate output contiene `(no project ADR directory)`, exit 0.
9. **Malformed settings.json degrades gracefully** — fixture con json invalido: section
   hook mostra `(unable to parse settings.json)`, overall status DEGRADED, exit 0.

Target PASS=9 nel proprio harness.

### 3.8 Anchor in `review-triage-fix` harness

+1 anchor per esistenza skill:

```bash
V="$HOME/.claude/skills/vibe-status/SKILL.md"
grep -q -- 'Vibe-Coding System Status' "$V" 2>/dev/null \
  && ok "vibe-status: SKILL.md present" \
  || bad "vibe-status: SKILL.md missing"
```

Harness PASS=47 → PASS=48. Bash 3.2-clean. Inserito prima della summary line, dopo gli
anchor esistenti.

### 3.9 Performance budget

| Section | Budget | Note |
|---|---|---|
| Args parse + discovery | 100ms | bash builtin glob/test |
| Harness parallel (3 harness × 2s avg, parallel) | 2-3s wall | timeout 8s ceiling |
| ADR parse (3 files × 50ms) | 200ms | grep+head |
| Manifest scan | 50ms | ls |
| Skill discovery | 50ms | ls |
| Settings.json parse | 100ms | jq |
| Triage state read | 50ms | jq if present |
| Memory head | 50ms | head -20 |
| Render markdown | 100ms | echo/printf |
| **Total typical** | **~3-4s** | well under 10s budget |
| **Total worst-case** | **~10s** | 1 harness near timeout |

### 3.10 Bash 3.2 cleanliness

- No assoc array → use temp dir for parallel results, file naming pattern.
- No `mapfile` → use `while read -r line; do ...; done < file`.
- No `${v^^}` → use `tr '[:lower:]' '[:upper:]'`.
- No `<()` process substitution → use temp file or pipeline.
- No `bash`-isms specific a 4.x.

Verify pre-deploy: `bash --version` su macOS = 3.2.57; lint con `shellcheck -s sh` mode.

---

## 4. Vincoli HARD (riconfermati da ADR)

- Bash 3.2.57 only.
- Read-only: skill NON modifica file di sistema. Solo legge.
- Performance <10s typical case.
- Anchor preservation: PASS=47 → PASS=48 nel harness `review-triage-fix`.
- Output stdout only (no file write).
- Fail-graceful: ogni section può degradare senza bloccare il report intero.
- No HITL nel design phase.

---

## 5. Cosa NON è in scope

- **Cache.** Re-run completo ogni invocazione. Defer v1.1.
- **Watch mode.** Skill è one-shot, non long-running. Defer v1.1.
- **Notifiche / alerting.** Skill è on-demand, non proactive. Defer.
- **Write-back / actions.** No skill modifica nulla. Defer separate skill.
- **Cross-project view.** Sempre cwd-relative + global. No multi-project aggregation.
- **Settings.json schema validation.** Solo parse jq, fail-graceful.

---

## 6. Open questions (validation pending dopo deploy)

1. Stefano usa effettivamente `/skill vibe-status` regolarmente?
2. Performance p95 con 5+ harness e session lunghi?
3. Markdown rendering in chat Claude Code è human-readable o serve `--plain`?

---

## 7. Riferimenti

- ADR: `docs/architecture/ADR-0005-vibe-status-skill.md`
- Pattern skill markdown: `~/.claude/skills/concept-to-code/SKILL.md`
- Pattern harness recente: `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`
- Pattern bash 3.2-clean timeout: `~/.claude/hooks/stop-gate.sh` linee 77-88
- Memory `feedback_bash32-constraint.md`
