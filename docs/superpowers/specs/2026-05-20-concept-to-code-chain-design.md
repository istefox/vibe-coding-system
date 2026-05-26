# `concept-to-code` skill orchestratore — Design Spec

**Status:** implementato — 2026-05-20
**Authors:** Adriano (architect agent) per Stefano Ferri
**Date:** 2026-05-20
**ADR:** `docs/architecture/ADR-0003-concept-to-code-chain.md` (Proposed)
**Plan:** `docs/superpowers/plans/2026-05-20-concept-to-code-chain.md` (drafted)

> Questa spec assume tutte le 10 decisioni dell'ADR-0003. Focus: contracts,
> interfaces, schema, state machine, path conventions. NON contiene codice di
> implementazione.

---

## 1. Goal & Scope

### Goal
Codificare il workflow concept→code (blueprint sez. 11) come skill markdown
chiamabile dall'orchestrator (`/skill concept-to-code <topic>`) con state machine
deterministica, manifest YAML persistente cross-session, HITL gates espliciti,
riuso delle skill custom esistenti (`interview-driver`, `adr-writer`,
`claude-md-generator`), e coexistenza ortogonale con le feature deployate
2026-05-20 (ADR-0001 + ADR-0002 + review-triage-fix v1.2).

### In-scope
- SKILL.md della skill `concept-to-code` (~250 righe) con prompt template
  versionato per dispatch architect/coder.
- 3 bash helper 3.2-clean in `~/.claude/skills/concept-to-code/scripts/`:
  - `manifest-init.sh` (crea manifest YAML iniziale al Step 1)
  - `manifest-validate.sh` (valida schema/state pre-resume)
  - `manifest-transition.sh` (transizioni state machine + state writeback)
- Self-test harness in `~/.claude/skills/concept-to-code/tests/run-tests.sh`
  (target PASS=10 FAIL=0).
- 2 nuovi anchor structural in `~/.claude/skills/review-triage-fix/tests/run-tests.sh`
  (target PASS=45 → PASS=47).
- Deliverable doc nel repo `vibe-coding-system`: ADR-0003, questa spec, plan,
  memory entry, MEMORY.md update.

### Out-of-scope
- Auto-mode flag per bypass HITL gates (futuro, candidate ADR-0004).
- Edit di `architect.md` o `coder.md` (decisione ADR §2.9: la skill non li
  modifica).
- Hook modifica (`~/.claude/hooks/` invariati).
- Notification OS-level / IDE integration.
- Migration tool per manifest schema v1.0 → v2.0 (rifattorizzazione manuale se
  serve).
- Slash command custom in `.claude/commands/` (scartato §2.1).
- Anchor harness su esistenza skill orchestrate (`interview-driver`,
  `adr-writer`, `claude-md-generator`) — candidate per future plan, fuori scope
  qui.

---

## 2. Manifest YAML schema

### 2.1 Path convention

Path del manifest (assoluto, nel progetto target):

```
<project-root>/docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml
```

Esempi concreti:
- `/Users/stefanoferri/Developer/pricing-markup-cli/docs/manifests/2026-05-22-rate-limiter.manifest.yml`
- `/Users/stefanoferri/Developer/swarm-testcmd/docs/manifests/2026-05-23-pipeline-fanout.manifest.yml`

`<topic-slug>` regole: lowercase, kebab-case, no spazi, no chars special,
max 40 chars. Esempi: `rate-limiter`, `pipeline-fanout`, `cli-config-loader`.

### 2.2 Schema completo (v1.0)

```yaml
# Campi obbligatori
manifest_schema_version: "1.0"
topic: "rate-limiter"                                  # slug, max 40 chars
topic_full_title: "Rate limiter middleware for FastAPI" # titolo human-readable
project_root: "/Users/stefanoferri/Developer/pricing-markup-cli"
created_at: "2026-05-22T14:35:00+02:00"                # ISO 8601 con timezone
last_updated_at: "2026-05-22T14:35:00+02:00"
current_step: "step_1_interview"                       # enum, vedi §3.1
status: "in_progress"                                  # enum: in_progress | failed | completed | aborted

# Artifacts (path assoluti, popolati man mano)
artifacts:
  spec: null                              # populated al Gate 1
  adr: null                               # populated al Gate 2 (path absolute)
  arch: null                              # populated al Gate 2 (ARCH.md path, optional)
  plan: null                              # populated al Gate 2
  project_claude_md: null                 # populated al Gate 3 (null se skip)

# HITL gates audit
hitl_gates:
  - gate: 1
    label: "spec_review"
    status: "pending"                     # enum: pending | approved | rejected | skipped
    approved_at: null
    notes: null                           # free-text dall'utente se rejection
  - gate: 2
    label: "architecture_review"
    status: "pending"
    approved_at: null
    notes: null
  - gate: 3
    label: "project_memory_review"
    status: "pending"
    approved_at: null
    notes: null
  - gate: 5
    label: "review_cycle_decision"
    status: "pending"
    approved_at: null
    notes: null

# Session boundary tracking
session_boundary:
  pre_step_4_session_id: null             # informativo, log-only
  fresh_session_started_at: null          # popolato dall'utente al resume
  resumed_at: null                        # popolato dalla skill su resume command

# Failure tracking (popolato solo su status=failed)
failure:
  failed_at: null
  failed_step: null
  failure_reason: null                    # string, es. "architect_timeout_60s"
  partial_artifacts: []                   # list di path .partial recuperabili

# Hint per prossima azione (UX)
next_action: "Awaiting user invocation of /skill concept-to-code resume <manifest-path> in fresh session"
```

### 2.3 Validazione

`scripts/manifest-validate.sh` controlla:
1. File esiste e leggibile.
2. `manifest_schema_version` presente ed è `"1.0"`.
3. `topic` non vuoto, matches `^[a-z0-9-]{1,40}$`.
4. `project_root` è directory esistente.
5. `current_step` ∈ enum (vedi §3.1).
6. `status` ∈ enum.
7. Se `status == "completed"`: tutti gli artifact non-null (eccetto
   `project_claude_md` che può essere null se skipped).
8. Se `status == "failed"`: `failure.failed_step` non null.
9. HITL gates: array di esattamente 4 elementi (gate 1, 2, 3, 5).

Exit codes: 0 = valido, 1 = invalido (con errore stderr), 2 = file
inesistente.

Bash 3.2 implementation: grep + sed parsing line-by-line, no YAML
library. Pattern già usato per `.claude/test-cmd` parsing in
`approve-test-cmd.sh`.

---

## 3. State Machine

### 3.1 States (enum `current_step`)

```
step_0_init                       # appena creato manifest, pre-interview
step_1_interview                  # Step 1 in corso (interview-driver active)
gate_1_spec_review                # in attesa di approval Gate 1
step_2_architecture               # Step 2 in corso (architect dispatched)
gate_2_architecture_review        # in attesa di approval Gate 2
step_3_project_memory             # Step 3 in corso (claude-md-generator active)
gate_3_project_memory_review      # in attesa di approval Gate 3
step_4_session_boundary           # checkpoint informativo, manifest committed
ready_for_implementation          # post Gate 3, pre resume
step_5_implementation             # post-resume, coder dispatched
step_6_review                     # opzionale, review cycle dispatched
gate_5_review_decision            # in attesa di approval Gate 5 (run/skip review)
completed                         # terminale (terminal state happy path)
failed                            # terminale (terminal state error)
aborted                           # terminale (terminal state user-abort)
```

### 3.2 ASCII state diagram

```
                    [START]
                       |
                       v
                  step_0_init
                       |
                       v
              step_1_interview --------+
                       |               | (interview fails)
                       v               v
            gate_1_spec_review      failed
              |          |
       reject |          | approve
              v          v
           (edit)    step_2_architecture --------+
              |          |                       | (architect fails)
              +<---------+                       v
                         v                    failed
              gate_2_architecture_review
                |              |
         reject |              | approve
                v              v
             (edit)        step_3_project_memory --------+
                |              |                          | (gen fails)
                +<-------------+                          v
                               v                       failed
                  gate_3_project_memory_review
                       |              |
                reject |              | approve | skip
                       v              v
                    (edit)      step_4_session_boundary
                       |              |
                       +<-------------+
                                      v
                            ready_for_implementation
                                      |
                                      v
                          [USER OPENS FRESH SESSION]
                                      |
                                      v
                  /skill concept-to-code resume <manifest>
                                      |
                                      v
                          step_5_implementation -------+
                                      |                | (coder fails)
                                      v                v
                            step_6_review            failed
                                  |       |
                                  |       | (skip review)
                                  v       v
                         gate_5_review_decision
                                  |       |
                            run   |       | skip
                                  v       v
                              completed
```

### 3.3 Transition table

| From                              | Event                  | To                                 | Side effect                              |
| --------------------------------- | ---------------------- | ---------------------------------- | ---------------------------------------- |
| `step_0_init`                     | start_interview        | `step_1_interview`                 | invoke `interview-driver`                |
| `step_1_interview`                | spec_written           | `gate_1_spec_review`               | display SPEC.md path + summary           |
| `gate_1_spec_review`              | user_approve           | `step_2_architecture`              | dispatch architect agent                 |
| `gate_1_spec_review`              | user_reject            | `step_1_interview`                 | re-invoke interview with feedback        |
| `step_2_architecture`             | adr_written            | `gate_2_architecture_review`       | display ADR + plan + key decisions       |
| `gate_2_architecture_review`      | user_approve           | `step_3_project_memory`            | invoke `claude-md-generator`             |
| `gate_2_architecture_review`      | user_reject            | `step_2_architecture`              | re-dispatch architect with feedback      |
| `step_3_project_memory`           | claudemd_written       | `gate_3_project_memory_review`     | display CLAUDE.md + diff if overwrite    |
| `gate_3_project_memory_review`    | user_approve           | `step_4_session_boundary`          | commit manifest, instruct fresh session  |
| `gate_3_project_memory_review`    | user_skip              | `step_4_session_boundary`          | (project_claude_md stays null)           |
| `gate_3_project_memory_review`    | user_reject            | `step_3_project_memory`            | re-invoke generator with feedback        |
| `step_4_session_boundary`         | manifest_committed     | `ready_for_implementation`         | print resume command to user             |
| `ready_for_implementation`        | resume_command         | `step_5_implementation`            | dispatch coder agent with manifest       |
| `step_5_implementation`           | coder_complete         | `step_6_review`                    | proceed to optional review               |
| `step_6_review`                   | review_decision_needed | `gate_5_review_decision`           | ask user run/skip review                 |
| `gate_5_review_decision`          | user_run               | `completed`                        | invoke review-triage-fix cycle, report   |
| `gate_5_review_decision`          | user_skip              | `completed`                        | skip review, report                      |
| any                               | tool_error             | `failed`                           | write .partial artifacts, set reason     |
| any                               | user_abort             | `aborted`                          | preserve artifacts, mark aborted         |

---

## 4. Skill API (input/output contract)

### 4.1 Invocation forms

The skill is invokable from the orchestrator in three forms:

**Form A: start new chain**
```
/skill concept-to-code <topic-full-title>
```
Esempio: `/skill concept-to-code Rate limiter middleware for FastAPI`

Behavior:
1. Genera `topic-slug` da `topic-full-title` (lowercase, kebab, max 40 chars).
2. Determina `project_root` come `$PWD` corrente.
3. Verifica che `docs/manifests/` esista (crealo se no, dopo HITL `mkdir
   docs/manifests` ack).
4. Verifica che NON esista già un manifest per stesso topic-slug stesso giorno
   (se esiste: errore "manifest già in progress, usa `resume`").
5. Invoca `scripts/manifest-init.sh` con args topic + project_root + title.
6. Transition `step_0_init` → `step_1_interview` → invoca `interview-driver`.

**Form B: resume from manifest**
```
/skill concept-to-code resume <manifest-path>
```
Esempio: `/skill concept-to-code resume /Users/stefanoferri/Developer/pricing-markup-cli/docs/manifests/2026-05-22-rate-limiter.manifest.yml`

Behavior:
1. Invoca `scripts/manifest-validate.sh <manifest-path>`. Exit non-0 → abort
   con errore parsing.
2. Legge `current_step`. Branch:
   - `ready_for_implementation` → dispatch coder (Step 5).
   - `step_1_interview..gate_3_project_memory_review` → errore "resume non
     necessario, sessione corrente può continuare".
   - `completed`/`aborted` → errore "chain terminato, crea nuovo manifest".
   - `failed` → errore "chain in failure state, manual recovery required".
3. Aggiorna `session_boundary.resumed_at` e `last_updated_at`.

**Form C: abort**
```
/skill concept-to-code abort <manifest-path>
```
Behavior: validate manifest, set `status: aborted`, set
`failure.failed_at: <now>`, no artifact deletion. Idempotent.

### 4.2 Output formats

**Per-step output** (mostrato all'utente alla fine di ogni Step prima del
relative Gate):

```
============================================================
concept-to-code · Step <N> · <step-name> COMPLETE
============================================================
Artifact: <absolute-path>
Summary:  <2-5 line summary>
Manifest: <manifest-path>
============================================================
HITL Gate <N>: <gate-label>
  [y] approve and proceed to Step <N+1>
  [e] reject and revise (provide notes)
  [s] skip (Gate 3 only)
  [a] abort chain
> _
```

**Final report** (Step 6 completion):

```
============================================================
concept-to-code · CHAIN COMPLETE
============================================================
Topic:        <topic-full-title>
Project:      <project_root>
Duration:     <total-elapsed>
Manifest:     <manifest-path>  (status: completed)

Artifacts:
  SPEC.md       <path>
  ADR-NNN.md    <path>
  ARCH.md       <path or "not generated">
  plan.md       <path>
  CLAUDE.md     <path or "skipped at Gate 3">

HITL gates passed:
  Gate 1 (spec_review):              approved at <timestamp>
  Gate 2 (architecture_review):      approved at <timestamp>
  Gate 3 (project_memory_review):    approved | skipped at <timestamp>
  Gate 5 (review_cycle_decision):    run | skipped at <timestamp>

Harness checks (if relevant project):
  review-triage-fix harness:  PASS=<N> FAIL=<M>
  project test-cmd:           <green | red | n/a>

Suggested memory entry (NOT auto-written):
  ## Project
  - [<topic>](project_<slug>.md) — DEPLOYED <date>: <one-line summary>

  Apply? [y] append to MEMORY.md  [s] skip
> _
============================================================
```

---

## 5. Path conventions for generated artifacts

| Artifact      | Path pattern (assoluto)                                                                | Notes                                          |
| ------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------- |
| SPEC.md       | `<project-root>/SPEC.md`                                                               | Posizione standard repo-root, invariata        |
| ADR           | `<project-root>/docs/architecture/ADR-NNN-<topic-slug>.md`                             | NNN incrementale, cfr. ADR-0001/0002/0003      |
| ARCH.md       | `<project-root>/ARCH.md`                                                               | Solo se architect ne produce uno (opzionale)   |
| plan          | `<project-root>/docs/superpowers/plans/YYYY-MM-DD-<topic-slug>.md`                     | Convenzione plan repo blueprint adottata       |
| Project CLAUDE.md | `<project-root>/CLAUDE.md`                                                         | Generato da claude-md-generator                |
| Manifest      | `<project-root>/docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml`                   | State machine persistence                      |

Convenzione `topic-slug` consistente attraverso tutti gli artifact: usata per
naming ADR, plan, manifest. Permette correlazione visiva immediata.

---

## 6. HITL gate contracts

Ogni gate ha 4 elementi contract:
- **Trigger:** quando si attiva.
- **Display:** cosa la skill mostra all'utente.
- **Wait:** input atteso.
- **Reject behavior:** cosa fa se utente rejecta.

### Gate 1 — Spec review

- **Trigger:** SPEC.md scritto da `interview-driver`, manifest aggiornato a
  `current_step: gate_1_spec_review`.
- **Display:**
  - Path SPEC.md (absoluto).
  - Summary 5 righe: obiettivo, scope, stack, edge case principali, success
    criteria.
  - Manifest path (per ispezione).
- **Wait:** `y` (approve) / `e` (reject with notes) / `a` (abort).
- **Reject behavior:** torna a `step_1_interview` con `notes` field popolato;
  `interview-driver` re-invocato con il feedback come prefix del prompt.

### Gate 2 — Architecture review

- **Trigger:** architect agent ritorna report con path ADR + plan; manifest
  aggiornato a `gate_2_architecture_review`.
- **Display:**
  - Path ADR, ARCH.md (se generato), plan.
  - Key decisions: list top-3 decisions estratte dall'ADR sezione `## 2.
    Decision`.
  - Risk flags: list risk presenti nell'output architect.
- **Wait:** `y` / `e` / `a`.
- **Reject behavior:** torna a `step_2_architecture`; architect re-dispatched
  con il feedback come addendum al brief.

### Gate 3 — Project memory review

- **Trigger:** `claude-md-generator` ha generato CLAUDE.md.proposed; manifest
  aggiornato a `gate_3_project_memory_review`.
- **Display:**
  - Se CLAUDE.md NON esiste: full content del file proposed (max 100 righe).
  - Se CLAUDE.md esiste: `diff CLAUDE.md CLAUDE.md.proposed` output.
- **Wait:** `y` (overwrite/create) / `e` (reject, revisiona) / `s` (skip, no
  CLAUDE.md change) / `a` (abort).
- **Reject behavior:** torna a `step_3_project_memory`; claude-md-generator
  re-invocato con feedback prefix.
- **Skip behavior:** `manifest.artifacts.project_claude_md = null`, transition
  a `step_4_session_boundary`.

### Gate 4 (informativo, NON bloccante) — Session boundary checkpoint

- **Trigger:** post Gate 3, manifest in `step_4_session_boundary`.
- **Display:**
  ```
  ============================================================
  concept-to-code · SESSION BOUNDARY
  ============================================================
  Steps 1-3 complete. Now:
  1. Close this Claude Code session.
  2. Open a NEW Claude Code session in: <project-root>
  3. Run: /skill concept-to-code resume <manifest-path>

  Reason: fresh session prevents context-window pollution from
  the interview/architecture turns.
  ============================================================
  ```
- **Wait:** none. La skill aggiorna `manifest.current_step =
  ready_for_implementation`, scrive `next_action` field, termina.

### Gate 5 — Review cycle decision

- **Trigger:** post Step 5 (coder dispatch complete); manifest a
  `gate_5_review_decision`.
- **Display:**
  - Coder report summary.
  - Files modified by coder.
  - Test harness result (project test-cmd if available).
  - Domanda: "Vuoi eseguire un review cycle review-triage-fix? Stima 5-10 min."
- **Wait:** `r` (run review) / `s` (skip) / `a` (abort).
- **Skip behavior:** transition `completed`, scrive final report.
- **Run behavior:** dispatch reviewer + skill review-triage-fix cycle, poi
  transition `completed`.

---

## 7. Interface contracts with orchestrated skills

### 7.1 `interview-driver` (Step 1)

**Invocation contract:**
- L'orchestrator, istruito dalla skill `concept-to-code`, invoca:
  ```
  Use the interview-driver skill to produce SPEC.md for topic:
  "<topic-full-title>".
  Project root: <project-root>.
  Save output to <project-root>/SPEC.md (the skill default).
  ```
- Su completion, l'orchestrator legge il path SPEC.md dal filesystem
  (`<project-root>/SPEC.md`) e popola `manifest.artifacts.spec`.

**Failure handling:** se `interview-driver` non produce `SPEC.md` entro 5
turns Q&A o l'utente abort esplicitamente, transition manifest a `failed`
con `failure_reason: "interview_aborted_or_incomplete"`.

### 7.2 `architect` agent (Step 2)

**Invocation contract:**
- L'orchestrator dispatch il sub-agent `architect` con prompt template
  letterale (versionato in SKILL.md):
  ```
  Read SPEC.md at <project-root>/SPEC.md.
  Produce:
  - ADR at <project-root>/docs/architecture/ADR-NNN-<topic-slug>.md (NNN
    incremental).
  - Plan at <project-root>/docs/superpowers/plans/YYYY-MM-DD-<topic-slug>.md
    (TDD plan style, 6-10 task).
  - Optional ARCH.md at <project-root>/ARCH.md if global architecture
    description needed.

  Constraints:
  - Auto mode active, no intermediate HITL.
  - Anchor-preserving on any harness present in the project.
  - Bash 3.2-clean for any helper script in plan.

  Return a report with: ADR path, plan path, ARCH path (or "n/a"), top 3 key
  decisions, top 3 risk flags.
  ```
- Su completion, l'orchestrator parse il report dell'architect (path
  espliciti) e popola `manifest.artifacts.{adr, plan, arch}`.

**Failure handling:** se architect ritorna report senza path validi
(es. API overload error pre-Write), transition `failed` con
`failure_reason: "architect_dispatch_failed:<reason>"`.

### 7.3 `claude-md-generator` (Step 3)

**Invocation contract:**
```
Use the claude-md-generator skill.
Read SPEC.md at <project-root>/SPEC.md and ARCH.md at <project-root>/ARCH.md
(if exists, else use ADR at <manifest.artifacts.adr>).
Generate CLAUDE.md.proposed at <project-root>/CLAUDE.md.proposed.

Do NOT overwrite <project-root>/CLAUDE.md if it exists — only write the
.proposed file. The concept-to-code skill handles the overwrite/skip
decision at Gate 3.
```

Su completion, la skill `concept-to-code` controlla esistenza
`<project-root>/CLAUDE.md`:
- Non esiste → display proposed content full → Gate 3.
- Esiste → run `diff CLAUDE.md CLAUDE.md.proposed` → display diff → Gate 3.

Su Gate 3 approve: `mv CLAUDE.md.proposed CLAUDE.md` (con backup
`.bak-<date>` se overwriting esistente).

**Failure handling:** se `claude-md-generator` non produce
`CLAUDE.md.proposed`, transition `failed` con
`failure_reason: "claude_md_generation_failed"`.

### 7.4 `coder` agent (Step 5)

**Invocation contract (post resume):**
```
Read plan at <manifest.artifacts.plan>.
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not
null).

Execute the plan task-by-task following TDD (red → green → checkpoint).
Use your Pre-flight Pattern Classifier (ADR-0001) for every Edit operation.

Auto mode active. No intermediate HITL.

Return a report with: tasks completed, files modified, test results, harness
deltas.
```

**Failure handling:** se coder fallisce mid-plan, manifest a `failed` con
`failure.partial_artifacts` popolato con i file edited fino al failure point.

### 7.5 `review-triage-fix` cycle (Step 6, opzionale)

**Invocation contract (post Gate 5 = run):**
```
Use the review-triage-fix skill.
Target: files modified by coder in step_5_implementation (see
manifest.artifacts.plan completion section).
Execute review-triage-fix v1.2 with Add+Remove rule.

Return final report.
```

**Failure handling:** review failures are non-blocking per il chain.
Transition `completed` con review report acluso al final report. Manifest
marca `gate_5.notes` con review outcome (es. "review found 2 MINOR,
0 MAJOR").

---

## 8. Coexistence invariants

### 8.1 Feature deployate 2026-05-20 — invariate

- `~/.claude/agents/coder.md` Pre-flight Pattern Classifier (ADR-0001): NON
  modificato. La skill non passa flag né override; il coder applica
  Pre-flight su ogni Edit nel Step 5 by-default.
- `~/.claude/agents/reviewer.md` item 5 Pattern-drift check (ADR-0001):
  NON modificato. Invocato implicitamente nel Step 6 review cycle.
- `~/.claude/agents/refactorer.md` Snapshot Harness Integration (ADR-0002):
  NON modificato. Out-of-band rispetto al chain (refactorer non è dispatched
  da concept-to-code).
- `~/.claude/skills/review-triage-fix/SKILL.md` v1.2 Add+Remove rule:
  NON modificato. Invocato letteralmente nel Step 6.

### 8.2 Skill custom esistenti — invariate

- `~/.claude/skills/interview-driver/SKILL.md`: NON modificato. La skill
  `concept-to-code` invoca il pattern naturale.
- `~/.claude/skills/adr-writer/SKILL.md`: NON invocato esplicitamente dalla
  skill `concept-to-code` (l'architect agent ha già contract per scrivere
  ADR direttamente in `docs/architecture/`; `adr-writer` resta skill
  utilizzabile per dispatch manuali).
- `~/.claude/skills/claude-md-generator/SKILL.md`: invocato in Step 3.
  Modifica richiesta: NESSUNA. La skill stessa produce `CLAUDE.md` di
  default; nel context della chain, l'orchestrator istruisce di scrivere a
  `CLAUDE.md.proposed` (vedi §7.3) — interpretazione dell'orchestrator del
  parametro path, non patch alla skill.

### 8.3 Hook / settings — invariati

- `~/.claude/hooks/approve-test-cmd.sh`, `stop-gate.sh`: invariati.
- `~/.claude/settings.json`: invariata.
- `~/.claude/.mcp.json`: invariata.
- `.claude/rules/`: invariate.

### 8.4 Harness invariants

- `~/.claude/skills/review-triage-fix/tests/run-tests.sh`: baseline PASS=45
  (2026-05-20 verified). Target post-feature: PASS=47 (+2 anchor su
  esistenza skill `concept-to-code` SKILL.md e su `manifest_schema_version`
  reference).
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`: baseline PASS=11
  (2026-05-20 verified). NON toccato da questo plan.
- Self-test della nuova skill: `~/.claude/skills/concept-to-code/tests/run-tests.sh`
  target PASS=10 (10 assertion: manifest schema, state transitions, resume
  semantics, override safe-to-restart, contract invariants).

---

## 9. Bash 3.2 helper contracts

### 9.1 `manifest-init.sh`

```
Usage: bash manifest-init.sh <topic-slug> <topic-full-title> <project-root>

Effect: write <project-root>/docs/manifests/<YYYY-MM-DD>-<topic-slug>.manifest.yml
        with current_step=step_0_init, status=in_progress, all artifacts null.

Exit: 0 ok | 1 docs/manifests/ not writable | 2 manifest already exists for
      same slug same day
```

### 9.2 `manifest-validate.sh`

```
Usage: bash manifest-validate.sh <manifest-path>

Effect: parse manifest via grep+sed (no YAML lib, bash 3.2-clean), check 9
        invariants (vedi §2.3). No stdout on success, errors to stderr.

Exit: 0 valid | 1 invalid | 2 file not found
```

### 9.3 `manifest-transition.sh`

```
Usage: bash manifest-transition.sh <manifest-path> <new-current-step> [<new-status>]

Effect: validate transition is legal (see §3.3 transition table), update
        current_step + last_updated_at + status (if provided). Atomic write
        via temp-file + mv.

Exit: 0 ok | 1 transition illegal | 2 manifest invalid pre-transition | 3
      write error
```

### 9.4 Self-test (`tests/run-tests.sh`)

10 assertion target:
1. `manifest-init.sh` crea file con schema v1.0 + current_step=step_0_init.
2. `manifest-init.sh` rifiuta doppia init stesso slug stesso giorno (exit 2).
3. `manifest-validate.sh` PASS su manifest fresh-init.
4. `manifest-validate.sh` FAIL su manifest senza `manifest_schema_version`.
5. `manifest-validate.sh` FAIL su `current_step` invalido.
6. `manifest-transition.sh` ammette `step_0_init → step_1_interview`.
7. `manifest-transition.sh` rifiuta `step_0_init → step_5_implementation`
   (skip illegale).
8. `manifest-transition.sh` aggiorna `last_updated_at` (different
   timestamp).
9. `manifest-validate.sh` su manifest a `status: completed` richiede
   `artifacts.spec`, `artifacts.adr`, `artifacts.plan` non-null.
10. `manifest-validate.sh` su `status: failed` richiede
    `failure.failed_step` non-null.

Stile identico a `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`
(11 assertion). Helpers `ok` / `bad` line counter.

---

## 10. Open questions for the plan phase

Tutte le 10 domande architetturali del brief hanno risposta finalizzata in
ADR-0003 sezione 2. Nessuna open question architetturale residua.

Open question implementative (per la plan phase / coder):
- **OQ-1:** generazione `topic-slug` da `topic-full-title` — algoritmo
  preciso? Proposta: lowercase + `tr -cs 'a-z0-9' '-'` + truncate a 40
  chars + trim trailing `-`. Da validare nel coder con test case.
- **OQ-2:** parsing del field `current_step` dal manifest in bash 3.2 —
  pattern preciso? Proposta: `grep '^current_step:' "$M" | sed 's/^current_step: *//;s/"//g'`.
  Stessa pattern già usato in `approve-test-cmd.sh` per `.claude/test-cmd`.
- **OQ-3:** atomic write del manifest — pattern? Proposta: `mktemp` + write
  + `mv` (atomic on POSIX). Standard idiom.

Queste sono dettagli di implementazione, non decisioni architetturali. Il
coder le risolve nel green phase, validate via self-test harness.

---

## 11. Future work (out of scope, candidate ADR-0004+)

- **Auto-mode flag** per skip Gate 1 e Gate 3 in cicli ripetitivi (NON Gate
  2 per safety).
- **Manifest cleanup tool** per archiviare/cancellare manifest abandoned
  (status in `in_progress` da >7 giorni → propose archive).
- **Anchor harness su skill orchestrate** — aggiungere anchor su esistenza
  `interview-driver/SKILL.md`, `claude-md-generator/SKILL.md` per protezione
  da deletion accidentale (rischio R-DEP-1 nell'ADR).
- **Cross-machine manifest portability** — risolvere il vincolo `path
  assoluti` se il workflow dovrà essere shared fra machine (oggi non
  problema).
- **CI integration** — gate Step 6 review automatizzabile in pipeline CI
  per progetti git-tracked (oggi review è interactive).
