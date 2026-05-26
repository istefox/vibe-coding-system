# ADR-0007 — End-to-end smoke test per concept-to-code chain

**Status:** Accepted — 2026-05-20 (implemented; concept-to-code harness PASS=12→13, +1 anchor composito; smoke-e2e.sh 3.78s wall; mutation test detection confermata)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (Accepted 2026-05-20; introduce
  la state machine 16-transition)
- `docs/superpowers/specs/2026-05-20-concept-to-code-e2e-smoke-design.md`
- `docs/superpowers/plans/2026-05-20-concept-to-code-e2e-smoke.md`
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine §3)
- `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (16 legal pairs)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh`
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (PASS=12 attuali — anchor)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_micropiano-refactor-cleanup.md` (rischio refactor cieco — composition test mitiga)

---

## 1. Context

Il self-test attuale (`tests/run-tests.sh`, 12 PASS) di concept-to-code copre i
3 script bash **isolati**:

- `manifest-init.sh` (assertion 1-2): crea manifest a path atteso, rifiuta
  double-init.
- `manifest-validate.sh` (assertion 3-5, 9-12): schema version, current_step,
  status invariants, invariant-7 quote/null.
- `manifest-transition.sh` (assertion 6-8): legal 0→1, illegal 0→5,
  last_updated_at refresh.

**Nessun test verifica la composizione completa** init → 16 transizioni
sequenziali → completed. Lo state machine ha 16 legal pairs (`manifest-transition.sh`
linee 36-52); attualmente solo 2-3 pairs sono coperti indirettamente.

Tre evidenze convergenti motivano l'intervento.

1. **Cycle 2 di pricing-markup-cli (memory `feedback_micropiano-refactor-cleanup.md`).**
   Un refactor che sostituisce un pattern senza explicit Add+Remove ha lasciato
   duplicazione. Stesso rischio per i 3 script di concept-to-code: un futuro
   refactor (es. aggiunta nuovo step, rinumerazione, normalizzazione PAIRS) può
   passare i 12 unit test ma rompere la composizione end-to-end. Manca il
   guard rail.

2. **State machine fragility.** Le 16 transizioni vivono in un heredoc (`PAIRS`
   temp file) dentro `manifest-transition.sh` linea 36+. Un typo nel pair
   (es. `step_5_implemenntation`) farebbe failing solo quando *un utente reale*
   tenta quella transizione — silent bug fino al campo. Smoke test che esercita
   tutte e 16 le pairs in sequenza catches il bug a deploy time.

3. **ADR-0003 menziona 16 transizioni come contract dichiarato** ma il self-test
   non lo verifica. Discrepanza tra documentazione (contract pubblico) e
   verifica eseguibile.

### Problema architetturale

Il chain concept-to-code è una *composizione* di 3 script + 16 transizioni
+ failure handling. La composizione non è testabile dagli unit test esistenti
(che testano script isolati con stato fresco). Serve un **integration smoke**
che esercita l'intera state machine come un orchestrator reale farebbe.

### Direzione

Aggiungere `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (bash 3.2-clean),
invocato come step finale di `tests/run-tests.sh` (composizione, non
sostituzione). Smoke coverage:

1. Init manifest fresco in tmpdir isolato.
2. Esegue tutte e 16 le legal transitions in sequenza happy path
   (incluso il branch `gate_5_review_decision → completed`).
3. Tenta 3 transizioni illegali (devono fallire con exit 1).
4. Forza una transizione `step_5_implementation → failed` (status forcing).
5. Verifica file consistency (`current_step`, `status`, `last_updated_at`
   monotonic) dopo ogni step rappresentativo.
6. Cleanup tmpdir via `trap EXIT`.

Tempo budget: <8s (target <5s; soft fail >10s).

---

## 2. Decision

Aggiungere `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`, eseguito
**dentro** `tests/run-tests.sh` come 13ª assertion composita (1 PASS = smoke
completo verde; 1 FAIL = smoke fallito a qualsiasi step interno, con stderr
che identifica lo step).

### 2.1 Architettura del smoke

```
smoke-e2e.sh
  setup:    TMP=$(mktemp -d); trap cleanup EXIT; PROJ=$TMP/proj
  init:     manifest-init.sh demo "Demo Feature" $PROJ → M=$PROJ/docs/manifests/...
  happy:    16 legal transitions in sequence, each followed by manifest-validate
  illegal:  3 illegal attempts (each must return exit 1)
  failure:  manifest-transition $M failed → must succeed, status=failed
  consistency: parse final manifest, assert current_step + status + timestamp
  emit:     SMOKE=PASS or SMOKE=FAIL:<phase>:<detail>
  exit:     0 PASS, 1 FAIL
```

Ogni "fase" emette una sub-line `OK` o `FAIL` su stderr per debug:

```
[smoke] setup OK
[smoke] init OK (path=/tmp/.../docs/manifests/...)
[smoke] happy 1/16 step_0→step_1 OK
[smoke] happy 2/16 step_1→gate_1 OK
...
[smoke] illegal 1/3 step_X→step_Y rejected OK
[smoke] failure-force OK status=failed
[smoke] consistency OK
SMOKE=PASS
```

### 2.2 Coverage delle 16 transizioni (happy path)

Sequenza che esercita tutte e 16 le pairs (incluso il branch
`step_5_implementation → gate_5_review_decision` direttamente, e il branch
"reject" di Gate 1/2/3 — backward transitions):

```
1.  step_0_init               → step_1_interview
2.  step_1_interview          → gate_1_spec_review
3.  gate_1_spec_review        → step_1_interview          (reject branch)
4.  step_1_interview          → gate_1_spec_review        (re-attempt)
5.  gate_1_spec_review        → step_2_architecture       (approve)
6.  step_2_architecture       → gate_2_architecture_review
7.  gate_2_architecture_review→ step_2_architecture        (reject branch)
8.  step_2_architecture       → gate_2_architecture_review (re-attempt)
9.  gate_2_architecture_review→ step_3_project_memory      (approve)
10. step_3_project_memory     → gate_3_project_memory_review
11. gate_3_project_memory_review → step_3_project_memory   (reject branch)
12. step_3_project_memory     → gate_3_project_memory_review (re-attempt)
13. gate_3_project_memory_review → step_4_session_boundary (approve)
14. step_4_session_boundary   → ready_for_implementation
15. ready_for_implementation  → step_5_implementation
16. step_5_implementation     → step_6_review
17. step_6_review             → gate_5_review_decision
18. gate_5_review_decision    → completed
```

Sono 18 transizioni; **tutte 16 le pairs distinte sono toccate**. Le 3 pairs
backward (3, 7, 11) sono "reject" branches, già nella PAIRS list. La pair
extra `step_5_implementation → gate_5_review_decision` (linea 52 di
`manifest-transition.sh`) NON è nel happy path qui — la verifichiamo in un
secondo mini-flow:

**Secondo flow (alternative path, fresh manifest):**

```
1'. step_0 → step_1 → gate_1 → step_2 → gate_2 → step_3 → gate_3 →
    step_4 → ready → step_5 → gate_5 (via shortcut step_5_implementation → gate_5_review_decision)
    → completed
```

Questo flow tocca la 16ª pair "shortcut" (skip step_6_review).

Totale coverage: 16/16 legal pairs verificate.

### 2.3 Illegal transitions (3)

Tentate da `step_0_init` su manifest fresco (replica logica assertion 7):

```
illegal 1: step_0_init → step_5_implementation    (skip ahead)
illegal 2: step_0_init → completed                 (jump-to-terminal)
illegal 3: step_0_init → gate_2_architecture_review (skip gates)
```

Tutte e 3 devono ritornare exit 1.

### 2.4 Failure-force test

Su un terzo manifest fresco (post-init), transizione diretta `step_0_init →
failed` (allowed unconditionally per `manifest-transition.sh` linea 31-32).
Verifica:
- exit 0,
- `grep '^status: "failed"' manifest` → match.

### 2.5 Risposte alle 4 domande architetturali

1. **Integrazione con harness esistente:** smoke-e2e.sh **affianca** ed è
   **invocato da** `run-tests.sh` come 13ª assertion composita. NON sostituisce
   gli unit test (che restano 12 PASS individuali). run-tests.sh esegue
   `bash tests/smoke-e2e.sh && PASS=PASS+1 || FAIL=FAIL+1`. Razionale:
   single-entry-point per il sistema (vibe-status legge un solo harness).
   Rationale negativo per "separato": diluisce il signal — gli utenti vedono
   un solo numero "PASS=N FAIL=0".

2. **Tmpdir cleanup:** `trap 'rm -rf "$TMP"' EXIT` per cleanup automatico
   ALWAYS. Su failure il tmpdir viene comunque cancellato (nessun debug
   artifact lasciato). **Flag `--keep-tmp` non implementato in v1** (YAGNI:
   smoke-e2e è deterministico; per debug si può commentare il trap nello
   script). Razionale: artefatti orfani in `/tmp` su CI = leak di disco;
   debug flag aggiunge complessità per un caso d'uso raro.

3. **Tempo di esecuzione target:** **<5s soft, <8s hard** su macOS 14+ con
   bash 3.2.57. Misurato con `time`. >8s = report come WARN nello stderr ma
   non fail. Razionale: i 3 script (`init`, `validate`, `transition`) sono
   ognuno ~50-100ms; 16 transitions × 100ms = 1.6s + 3 illegal × 100ms = 0.3s
   + failure force = 0.1s + setup/teardown = 0.5s ≈ 2.5s wall. Margine 2x
   per dischi lenti.

4. **Coverage delle transizioni:** **tutte e 16 le legal + 3 illegal
   rappresentative + 1 failure-force.** Razionale: il valore aggiunto è
   esattamente la *completezza* — un smoke che copre 12/16 lascia 4 buchi
   silenziosi (lo stesso problema che vogliamo risolvere). Le 3 illegal sono
   "representative" non "exhaustive" (combinatoria 15×14 non praticabile;
   3 esempi coprono pattern: skip-ahead, jump-terminal, skip-gates).
   Trade-off: completezza vince per scope ristretto (16 è un numero piccolo
   e fisso).

---

## 3. Alternatives considered

### Alt-A — Smoke separato, NON invocato da `run-tests.sh` (RIFIUTATA)

Smoke vive in `tests/smoke-e2e.sh` ma è invocato solo on-demand
(`bash tests/smoke-e2e.sh`).

**Rifiuto:**
- Skill `vibe-status` (ADR-0005) legge un solo harness per skill — vedere
  un PASS=12 quando esiste anche un smoke separato non eseguito è
  misleading. Single-entry-point preserva il contract aggregator.
- Test che non gira di default = test che marcisce. Cycle 2 lesson:
  "un check che richiede ricordo umano è già un check non funzionante".

### Alt-B — Smoke come Python script che parsa il YAML manifest (RIFIUTATA)

Usare PyYAML per parsing rigoroso del manifest dopo ogni transizione.

**Rifiuto:**
- Bash 3.2 constraint hard (sez. 0 del CLAUDE.md di sistema). Aggiungere
  dipendenza Python a un self-test di skill che è 100% bash è un cross-stack
  smell.
- I 3 script target (`init`, `validate`, `transition`) sono già bash; il
  loro contract è grep/sed-friendly. PyYAML aggiunge superficie senza
  beneficio dimostrabile.

### Alt-C — Subset rappresentativo (8/16 transitions) (RIFIUTATA)

Coverage parziale (es. solo happy path 5-step, niente backward branches).

**Rifiuto:**
- Lascia 8 pairs unverified — stesso problema di oggi al 50%. Il valore
  aggiunto del smoke E2E è esattamente catturare i pair "ribelli" (reject
  branches, shortcut step_5→gate_5).
- Sequence è 18 transitions ≈ 2s wall — il guadagno tempo è marginale; il
  rischio di copertura è alto. Decisione costo/beneficio chiara per la
  completezza.

---

## 4. Consequences

### Positive

- Refactor futuri di `manifest-transition.sh` (es. aggiunta nuovo step,
  rinumerazione gate) catturati immediatamente da smoke fail.
- Contract dichiarato (16 transitions) ora verificato eseguibile, non solo
  documentato.
- `vibe-status` riporta PASS=13 (era 12) — single number aggregato dello
  stato concept-to-code skill.
- Coverage state machine: da 2-3/16 → 16/16 + 3 illegal + 1 failure-force.

### Negative

- Nuovo file da mantenere (`smoke-e2e.sh`, ~80-100 righe bash).
- run-tests.sh tempo esecuzione cresce di ~2-3s (era <1s). Acceptable.
- Se il smoke FAIL, debug richiede leggere stderr line `[smoke] phase X
  step_Y→step_Z FAIL <detail>` invece di assertion individuale. Mitigation:
  stderr verboso con un line per ogni transizione.

### Neutral

- Smoke esercita gli stessi 3 script degli unit test; non aggiunge code
  coverage di logica nuova, solo *composition*.
- Tmpdir cleanup unconditional su EXIT trap; nessun residuo in `/tmp`.

---

## 5. References

- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (linee
  36-52: 16 PAIRS list — ground truth)
- `~/.claude/skills/concept-to-code/SKILL.md` §3 (state machine summary)
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (12 assertion
  unit — preserved intatte)
- ADR-0003 §2 (transition table — contract dichiarato)
