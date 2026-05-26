# ADR-0006 — `RFS_RUNS=N` configurable determinism check per refactor-snapshot

**Status:** Accepted — 2026-05-20 (implemented; refactor-snapshot harness PASS=11→18, +7 anchor; RFS_DETERMINISM_RUNS dead code eliminated; smoke 4/4 scenarios OK)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/architecture/ADR-0002-refactor-snapshot-harness.md` (Accepted 2026-05-20, est. dei 3 PRE run hardcoded)
- `docs/superpowers/specs/2026-05-20-refactor-snapshot-runs-configurable-design.md`
- `docs/superpowers/plans/2026-05-20-refactor-snapshot-runs-configurable.md`
- `~/.claude/agents/refactorer.md` (Step 3 hardcoded "re-run pre-snapshot 2 more times (3 total)")
- `~/.claude/skills/refactor-snapshot/SKILL.md` (cita già `RFS_DETERMINISM_RUNS` ma non implementato)
- `~/.claude/skills/refactor-snapshot/scripts/capture.sh` (single-shot, non itera)
- Memory `feedback_bash32-constraint.md`

---

## 1. Context

Il refactor-snapshot harness (ADR-0002, deployato 2026-05-20) impone al refactorer
3 esecuzioni del PRE snapshot (Step 3 di `refactorer.md`: "Re-run pre-snapshot 2
more times (3 total). If SHA256 differs across runs → STOP"). Il numero **3** è
hardcoded nel prompt; `capture.sh` non sa nulla del concetto di "run set" — è
single-shot.

Tre evidenze convergenti motivano l'intervento.

1. **Discrepanza già presente nel codice.** `SKILL.md` cita la env var
   `RFS_DETERMINISM_RUNS` (default 3) come *parte del contract pubblico*, ma né
   `capture.sh` né `refactorer.md` la onorano. È un contratto dichiarato e non
   implementato — un bug latente di documentazione.

2. **Test suite lente.** Su progetti reali (pricing-markup-cli ha test-cmd da
   ~90s; il blueprint vibe-coding-system ha harness aggregati >120s) un PRE da 3
   esecuzioni vale 4.5–6 minuti *prima* del refactor + 1 POST = 6–8 minuti per
   ogni *pass* di refactor (≤200 lines), tipicamente 3-5 pass per feature → 30-40
   minuti di friction. Quando il test è notoriamente deterministico, l'utente
   vuole abbassare a `RFS_RUNS=1` (skip determinism, accettare il rischio).

3. **Test flaky.** I test che falliscono 1/10 hanno solo
   `1 - (0.9)^3 ≈ 27%` chance di essere catturati a 3 run. Per progetti con
   suite note-flaky (test integration, async I/O) servono 5-10 run per ridurre
   il false-negative rate a <5%. Hardcoded 3 dà un *false sense of security*.

### Problema architetturale

Il valore "3" è una *policy* (compromesso costo/coverage) hardcoded in un *prompt*
(`refactorer.md`) e ignorato dal layer eseguibile (`capture.sh`). Mancano sia la
configurabilità sia il single source of truth: il numero di run vive in due posti
(prompt + SKILL.md cita ma non honors) e in nessuno dei due è autoritativo
runtime.

### Direzione

Implementare `RFS_RUNS=N` come *vera* env var:

- Letta da un **nuovo wrapper script** `pre-runs.sh` (sibling di `capture.sh`,
  `diff.sh`).
- Default 3, range valido [1, 10], validazione esplicita (fail loud).
- Il refactorer chiama il wrapper *una sola volta* invece di 3 invocazioni a
  `capture.sh PRE`.
- Audit trail: l'output del wrapper include `RUNS=N` esplicito; il report del
  refactorer cita il valore effettivo usato.

Rinominata `RFS_DETERMINISM_RUNS` → `RFS_RUNS` (breve, allineato a
`RFS_TIMEOUT`/`RFS_FILTER`/`RFS_FULL`). La var `RFS_DETERMINISM_RUNS` non era mai
stata onorata dal codice eseguibile, quindi questo è un cambio del SKILL.md ma
non un breaking change runtime.

---

## 2. Decision

Introdurre un nuovo script eseguibile
`~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh` (bash 3.2-clean) con
contract:

```
bash pre-runs.sh
# Reads env: RFS_RUNS (default 3, range [1,10])
# Calls capture.sh PRE N times.
# Compares SHA256 (STDOUT + STDERR + EXIT) of every snapshot vs first.
# Emits to stdout: RUNS=<N>\nSTATUS=<PASS|UNVERIFIED>\n[FIRST_RUN_SHA=...]
# Exit: 0 PASS, 2 UNVERIFIED, 1 invalid RFS_RUNS, 3 capture.sh failure
```

Comportamento dettagliato:

- `RFS_RUNS=N` validato come intero in [1, 10]. Out-of-range o non-numerico →
  exit 1, stderr `ERROR: RFS_RUNS=<val> invalid, must be integer in [1,10]`.
  **Fail loud, NO clamp silenzioso.**
- `N=1` esegue 1 capture, emette `STATUS=PASS` automaticamente (nessun
  determinism check possibile a N=1, ma è una scelta esplicita dell'utente —
  audit trail nel report dirà `RUNS=1 (determinism check skipped)`).
- `N≥2` esegue N capture; dopo ogni capture salva il file in tmp con SHA256
  calcolato; confronta tutti contro il primo. Se anche solo uno differisce →
  `STATUS=UNVERIFIED`, exit 2. Tutti uguali → `STATUS=PASS`, exit 0. Il file
  PRE finale (`.claude/.refactor-snapshot.txt`) è quello dell'ULTIMA run (più
  recente = baseline più aggiornata).
- Se una singola `capture.sh` interna fallisce (exit≠0, es. missing test-cmd,
  timeout) → propagato come exit 3, stderr include la run number che ha
  fallito.

Wording `refactorer.md` Step 3 cambia da:

```
3. Determinism check. Re-run pre-snapshot 2 more times (3 total). If SHA256
   differs across runs → STOP, output `UNVERIFIED non-deterministic test output`...
```

a:

```
3. PRE capture + determinism check. Invoke
   `bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`.
   Default 3 runs; override via `RFS_RUNS=<1..10>` env var. Exit 0 = PASS, exit 2
   = UNVERIFIED (non-deterministic across runs). Cite the RUNS=N value from
   stdout in the final report.
```

Le invocazioni precedenti `capture.sh PRE` (Step 2 e Step 3) collassano in
*una sola invocazione* di `pre-runs.sh`. Il refactor lifecycle diventa:

```
pre-runs.sh                         # PRE + determinism (Steps 2+3 fusi)
# ... refactor edits ...
capture.sh POST
diff.sh
```

### 2.1 Coexistence con altre env var

`RFS_RUNS` coesiste ortogonalmente con `RFS_TIMEOUT`, `RFS_FILTER`, `RFS_FULL`:

- `RFS_TIMEOUT` è **per-run** (no cambiamento — ogni invocazione di `capture.sh`
  dentro `pre-runs.sh` rispetta il proprio timeout). Wallclock totale worst-case
  ≈ `N * RFS_TIMEOUT`.
- `RFS_FILTER` / `RFS_FULL` sono **per-capture**, identici per tutte le N run
  (no random selection — tutte le run usano la stessa scope altrimenti il
  determinism check è impossibile).
- Audit trail nel report del refactorer: cita esplicitamente `RUNS=N`,
  `TIMEOUT=...`, `FILTER=...`/`FULL=...` quando non-default.

### 2.2 Risposte alle 4 domande architetturali

1. **Granularità del controllo:** env var globale `RFS_RUNS` *sessione-only*.
   No file di config per-progetto in questa iterazione (YAGNI: il refactorer
   è invocato in sessione interattiva, l'utente sa quale progetto sta toccando
   e può prefissare `RFS_RUNS=5 ` al dispatch). File di config aggiunge
   parsing logic + casi di precedence (env > file > default) per zero
   beneficio dimostrato.

2. **Validazione di N:** **fail loud, no clamp.** `RFS_RUNS=0` e `RFS_RUNS=11`
   sono errori espliciti (exit 1). Razionale: clamp silenzioso nasconde bug
   nel call site; "0 = skip determinism" è un'ambiguità (è skip o è errore?).
   Il caso "skip determinism" è esplicito come `RFS_RUNS=1` (vedi sopra).

3. **Wording Step 3 + audit trail:** report del refactorer cita
   `RUNS=N` letteralmente da stdout del wrapper. Default 3 = cita "RUNS=3
   (default)"; override = cita "RUNS=5 (env override)". Il file
   `.claude/.refactor-snapshot.txt` NON contiene il valore N (resta byte-for-byte
   compatibile con ADR-0002 format: EXIT/SHA/SHA/---/---/). Audit trail vive
   nel report markdown del refactorer, non nello snapshot file (separation of
   concerns: snapshot = byte-faithful behavior; report = process metadata).

4. **Cohesion con altri flag:** vedi §2.1. Coesistono per design; nessun
   cross-effect. `RFS_RUNS=10 + RFS_TIMEOUT=120` = worst-case 20 minuti su
   PRE — è una scelta consapevole, l'utente lo vede.

---

## 3. Alternatives considered

### Alt-A — Mutare `capture.sh` con loop interno (RIFIUTATA)

Aggiungere il loop dentro `capture.sh PRE` quando `RFS_RUNS≥2`.

**Rifiuto:**
- Viola single-responsibility: `capture.sh` oggi cattura *uno* snapshot.
  Cambiarlo in "1 o N a seconda di env var" lo rende stateful.
- Rompe il contract dichiarato in `SKILL.md` invocazione contract (3 chiamate
  esplicite). Devo riscrivere comunque sia SKILL.md sia agente — meno isolato
  del wrapper.
- I 10 test self-test esistenti di `capture.sh` dovrebbero essere riveduti
  uno-a-uno; wrapper isolato preserva l'anchor self-test esistente intatto.

### Alt-B — Loop nel prompt del refactorer, leggere `RFS_RUNS` come testo (RIFIUTATA)

Il prompt `refactorer.md` Step 3 dice "execute `capture.sh PRE` $RFS_RUNS times,
compare SHA256 by reading the files". Lo Claude-agent interpreta il loop.

**Rifiuto:**
- Non-deterministico: l'agente potrebbe sbagliare il count, dimenticare il
  confronto, etc. Spostare logica deterministica in un agente probabilistico
  è anti-pattern (lezione di ADR-0002: il valore aggiunto del harness è la
  *deterministica* del check).
- Non testabile via bash harness: il loop non esiste fisicamente in un file
  eseguibile. ZERO copertura possibile dal self-test.

### Alt-C — File di config `.claude/refactor-snapshot.config` (RIFIUTATA per ora)

Override per-progetto via file YAML con `runs: 5`.

**Rifiuto:**
- YAGNI: nessuna evidenza di richiesta. Aggiunge parser YAML in bash 3.2
  (costoso). L'env var copre 100% del caso d'uso identificato (sessione interattiva).
- Precedence rules (file > env > default? env > file? per-cwd o per-user?)
  introducono complessità senza beneficio dimostrato. Riapribile in ADR
  successivo se emerge il use case.

---

## 4. Consequences

### Positive

- Refactor su suite lente diventa praticabile (`RFS_RUNS=1`).
- Refactor su suite flaky diventa rigoroso (`RFS_RUNS=8`).
- SKILL.md torna coerente con il codice (single source of truth: `pre-runs.sh`).
- Una sola invocazione (`pre-runs.sh`) sostituisce 3 (`capture.sh PRE` ×3) →
  refactorer prompt più semplice, meno scope per errori interpretativi.
- Audit trail esplicito (`RUNS=N` nel report del refactorer).

### Negative

- Nuovo file eseguibile da mantenere (`pre-runs.sh`). +1 superficie di test
  (target: +6 PASS al self-test refactor-snapshot, 11 → 17).
- Refactorer.md cambia → un altro Edit sul prompt critico (ma minimo: 2 righe).

### Neutral

- `RFS_DETERMINISM_RUNS` (citata in SKILL.md ma mai onorata) viene rinominata
  in `RFS_RUNS`. Non è un breaking change runtime (la vecchia var non faceva
  nulla); è un cambio di documentazione.
- Il file `.claude/.refactor-snapshot.txt` finale è quello dell'ultima run
  (non della prima). Equivalente quando determinism PASS; più informativo
  quando UNVERIFIED (ultimo stato osservato).

---

## 5. References

- `~/.claude/skills/refactor-snapshot/scripts/capture.sh` (single-shot, da non
  modificare)
- `~/.claude/skills/refactor-snapshot/scripts/diff.sh` (orthogonale)
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` (anchor; ne aggiungiamo
  test, non ne tocchiamo di esistenti)
- ADR-0002 §2 (3 PRE run hardcoded — soft-superseded dal default 3 di
  `RFS_RUNS`)
