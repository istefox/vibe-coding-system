# Field Test Runbook — pricing-markup-cli

> **Modalità:** runbook INTERATTIVO guidato dall'utente (NON batch autonomo — vedi spec sez.3bis). L'utente esegue ogni step in una sessione `claude` dentro il pilota; l'assistente (sessione di coordinamento corrente) fornisce i passi e registra le osservazioni nel log. Step con checkbox `- [ ]` per tracciamento.
> **Git:** il pilota `~/developer/pricing-markup-cli` ha git proprio (commit lì appropriati). Il repo `vibe-coding-system` resta no-git (ci vive solo il log).

**Goal:** Eseguire il workflow concept→code reale su una piccola CLI Python di pricing per validare trigger e `description` di skill/agenti del sistema deployato.

**Architecture:** Progetto pilota separato con git. Workflow: interview→SPEC→architect/ADR→claude-md-generator→coder→tester→bug deliberato→debugger→reviewer. Output = log osservazioni in `vibe-coding-system/docs/field-test-2026-05-18.md` con tabella trigger e lista tweak `description`.

**Tech Stack:** Python 3.12, `argparse`, `decimal.Decimal`, pytest. Le skill/agenti del sistema vibe coding deployato.

**Definizione CLI (target concreto per gli agenti):**
- Args: `--cost FLOAT` (≥ 0), `--markup FLOAT` (percentuale, può essere > 100, ≥ 0), `--rounding {half-up,half-even}` (default `half-up`).
- Calcolo: `price = Decimal(cost) * (1 + Decimal(markup)/100)`, poi `quantize(Decimal('0.01'))` con `ROUND_HALF_UP` o `ROUND_HALF_EVEN`.
- Errori: input negativi o non numerici → messaggio su stderr + exit code 2.
- Output: prezzo con 2 decimali su stdout, exit 0.

---

## File Structure

| File | Responsabilità |
|---|---|
| `~/developer/pricing-markup-cli/SPEC.md` | Prodotto da `/interview-driver` |
| `~/developer/pricing-markup-cli/docs/architecture/ADR-001-rounding.md` | Prodotto da agente `architect` |
| `~/developer/pricing-markup-cli/CLAUDE.md` | Prodotto da `/claude-md-generator` |
| `~/developer/pricing-markup-cli/src/pricing_markup/cli.py` | Implementato da agente `coder` |
| `~/developer/pricing-markup-cli/tests/test_cli.py` | Implementato da agente `tester` |
| `vibe-coding-system/docs/field-test-2026-05-18.md` | Log osservazioni (lo mantiene l'assistente) |

---

### Task 0: Setup del pilota (utente)

- [ ] **Step 1: crea progetto + git + venv**

Nel terminale:
```
! mkdir -p ~/developer/pricing-markup-cli && cd ~/developer/pricing-markup-cli && git init && python3 -m venv .venv && source .venv/bin/activate && pip install pytest && echo "SETUP OK"
```
Atteso: `SETUP OK`, cartella con `.git/` e `.venv/`.

- [ ] **Step 2: avvia la sessione Claude nel pilota**

```
cd ~/developer/pricing-markup-cli && claude
```
Da qui in poi gli step `/...` e `@...` si eseguono **dentro questa sessione**.

- [ ] **Step 3 (assistente): inizializza il log**

L'assistente crea `vibe-coding-system/docs/field-test-2026-05-18.md` con lo scheletro (tabella di sez. "Log" sotto). Nessuna azione utente.

---

### Task 1: Interview → SPEC.md (valida `interview-driver`, `disable-model-invocation`)

- [ ] **Step 1: invoca la skill a mano**

Nella sessione del pilota digita:
```
/interview-driver CLI Python per calcolo prezzo con markup (cost, markup %, regola di arrotondamento)
```

- [ ] **Step 2: rispondi all'interview**

Rispondi alle domande `AskUserQuestion` (rounding half-up vs half-even default, gestione input negativi, precisione 2 decimali, formato output). Lascia che scriva `SPEC.md`.

- [ ] **Step 3: osservazione da riportare all'assistente**

Riporta: (a) la skill si è attivata SOLO col comando esplicito e NON in automatico prima? (atteso: sì, ha `disable-model-invocation`); (b) le domande erano pertinenti o ovvie/fuori tema? (c) `SPEC.md` creato e sensato? L'assistente registra nel log riga `interview-driver`.

---

### Task 2: architect → ADR rounding (valida agente `architect`)

- [ ] **Step 1: invoca l'agente**

```
@"architect (agent)" leggi SPEC.md e produci docs/architecture/ADR-001-rounding.md con la decisione su ROUND_HALF_UP vs ROUND_HALF_EVEN, precisione Decimal a 2 decimali, gestione input negativi. Non scrivere codice produttivo.
```

- [ ] **Step 2: HITL**

Rivedi l'ADR. Approva o chiedi correzioni.

- [ ] **Step 3: osservazione**

Riporta: l'agente ha rispettato il vincolo "nessun codice produttivo"? Ha prodotto l'ADR nella struttura attesa (Status/Context/Decision/Alternatives/Consequences/References)? Ha provato a usare `sequential-thinking` MCP (graceful)? L'assistente registra riga `architect`.

---

### Task 3: claude-md-generator → CLAUDE.md (valida degrado grazioso fuori-template)

- [ ] **Step 1: invoca la skill**

```
/claude-md-generator
```

- [ ] **Step 2: osservazione chiave**

Una CLI Python pura non combacia con nessuno dei 3 template (app-fastapi-react/web-vanilla/ios-swiftui). Riporta: la skill ha **degradato con grazia** (es. ha generato un CLAUDE.md generico sensato, o ha chiesto, o ha scelto male)? È < ~100 righe e lean (eredita il globale, niente duplicazioni)? L'assistente registra riga `claude-md-generator` — questo è un punto di tweak probabile.

---

### Task 4: coder → implementazione (valida agente `coder`, rule python.md, hook auto-format)

- [ ] **Step 1: invoca l'agente**

```
@"coder (agent)" implementa src/pricing_markup/cli.py seguendo ADR-001 e SPEC.md: argparse (--cost, --markup, --rounding half-up|half-even default half-up), Decimal, quantize 0.01, errori su input negativi/non numerici con exit 2. Non committare.
```

- [ ] **Step 2: osservazione**

Riporta: il `coder` ha letto ADR/SPEC e file simili prima? Ha usato `Decimal` (no float)? Ha verificato (eseguito) prima di dire "fatto"? Ha rispettato "non committare"? **Hook**: dopo l'edit del `.py`, `auto-format.sh` ha riformattato (ruff)? La **rule `python.md`** risulta caricata (type hint, docstring Google, logging)? L'assistente registra righe `coder`, `hook auto-format`, `rule python.md`.

- [ ] **Step 3: commit (nel pilota)**

```
git add -A && git commit -m "feat: pricing markup CLI per ADR-001"
```

---

### Task 5: tester → pytest (valida agente `tester`)

- [ ] **Step 1: invoca l'agente**

```
@"tester (agent)" scrivi tests/test_cli.py con pytest: happy path, arrotondamento .5 half-up vs half-even, costo/markup negativi (exit 2), zero, markup > 100. Esegui la suite.
```

- [ ] **Step 2: osservazione**

Riporta: i test coprono gli edge case dell'ADR? Naming `test_*`? Ha eseguito la suite e riportato pass/fail? Ha evitato di modificare codice produttivo? L'assistente registra riga `tester`.

- [ ] **Step 3: commit**

```
git add -A && git commit -m "test: edge case pricing/rounding"
```

---

### Task 6: bug deliberato → debugger (valida agente `debugger`)

- [ ] **Step 1: introduci il bug a mano**

In `src/pricing_markup/cli.py`, nella funzione di arrotondamento, sostituisci la quantizzazione `Decimal` con un `round(float(price), 2)` Python (che usa banker's rounding sul float) **solo per il ramo `half-up`**. Effetto: i casi `.5` su `half-up` arrotondano in modo errato vs ADR. Salva. (Non committare il bug.)

- [ ] **Step 2: fai fallire un test**

```
pytest -q
```
Atteso: il/i test su `.5 half-up` FALLISCONO.

- [ ] **Step 3: invoca il debugger**

```
@"debugger (agent)" pytest fallisce sui casi .5 con --rounding half-up. Trova la root cause e applica il fix minimo, niente soppressione sintomi.
```

- [ ] **Step 4: osservazione**

Riporta: il `debugger` ha identificato la **root cause vera** (uso di `round()` float invece di `Decimal.quantize` ROUND_HALF_UP) e non un sintomo? Fix minimo? Ha aggiunto/verificato un test di regressione? L'assistente registra riga `debugger`.

- [ ] **Step 5: commit del fix**

```
pytest -q && git add -A && git commit -m "fix: rounding half-up usa Decimal.quantize (era round() float)"
```

---

### Task 7: reviewer → report (valida agente `reviewer`)

- [ ] **Step 1: invoca l'agente**

```
@"reviewer (agent)" rivedi le modifiche recenti (git diff) per sicurezza, correttezza, performance, consistenza. Output per severità.
```

- [ ] **Step 2: osservazione**

Riporta: output in BLOCKER/MAJOR/MINOR/NIT con `file:line`? Solo read-only (no edit)? Ha provato a usare la skill `code-review-checklist` (graceful)? L'assistente registra riga `reviewer`.

---

### Task 8: Assemblaggio deliverable (assistente)

- [ ] **Step 1:** l'assistente completa `vibe-coding-system/docs/field-test-2026-05-18.md`: tabella trigger compilata + sezione "Mis-fire/no-fire" + **lista concreta di tweak `description`/prompt** derivata dalle osservazioni.

- [ ] **Step 2:** l'assistente presenta il riepilogo + la lista tweak proposta. NESSUNA modifica a skill/agenti in questo runbook (i tweak si applicano in un ciclo separato — spec sez.6).

---

## Log — template tabella (lo compila l'assistente in `field-test-2026-05-18.md`)

```markdown
# Field test 2026-05-18 — pricing-markup-cli

| Skill/Agente | Trigger atteso | Trigger reale | Auto/Manuale OK | Esito | Note/mis-fire |
|---|---|---|---|---|---|
| interview-driver | solo manuale (/), produce SPEC.md | | | | |
| architect | @agent, ADR, no codice prod | | | | |
| claude-md-generator | manuale, degrada grazioso fuori-template | | | | |
| coder | @agent, Decimal, no commit | | | | |
| rule python.md | caricata su *.py | | n/a | | |
| hook auto-format | riformatta dopo edit .py | | n/a | | |
| hook protect-files | blocca file protetti se toccati | | n/a | | |
| tester | @agent, pytest edge, no codice prod | | | | |
| debugger | @agent, root cause vera, fix minimo | | | | |
| reviewer | @agent, severità, read-only | | | | |
| auto mode | nessun falso blocco su azione legittima | | n/a | | |

## Mis-fire / no-fire osservati
- (frase scatenante → comportamento errato)

## Tweak proposti (description/prompt) — da applicare in ciclo separato
- (agente/skill → modifica concreta)
```

---

## Self-Review (eseguita in scrittura piano)

**1. Spec coverage:** progetto pilota→Task0; interview-driver→Task1; architect/ADR→Task2; claude-md-generator+degrado→Task3; coder+rule+hook→Task4; tester→Task5; bug+debugger→Task6; reviewer→Task7; deliverable+tabella+tweak→Task8/Log; modalità interattiva→header+ruoli espliciti; git pilota sì / blueprint no→header+commit negli step. Tutto coperto.

**2. Placeholder scan:** nessun TBD/TODO; comandi/prompt esatti; il bug deliberato è specificato esattamente (`round()` float al posto di `Decimal.quantize` sul ramo half-up); la tabella è un template concreto, non "riempi". OK.

**3. Consistency:** path pilota coerente ovunque (`~/developer/pricing-markup-cli`); nomi agente/skill coerenti col sistema deployato; `disable-model-invocation` atteso solo su interview-driver (coerente con spec); git solo nel pilota. OK.

**4. Adattamenti dichiarati:** runbook interattivo non autonomo; "test" = protocollo osservazione; commit nel pilota OK, blueprint no-git; nessuna modifica skill/agenti durante il test. OK.
