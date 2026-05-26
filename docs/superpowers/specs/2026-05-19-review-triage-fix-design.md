# Design — Skill `review-triage-fix`

**Data:** 2026-05-19
**Stato:** approvato → implementato → v1.1 (post-pilot parziale 2026-05-19) → v1.2 (2026-05-20 Add+Remove rule) — piano `docs/superpowers/plans/2026-05-19-review-triage-fix.md` (sezione "v1.2"); spec v1.2 `docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`; harness 41/41; pilota organico v1.1+v1.2 pending (Stefano-run)
**Autore:** Adriano per Stefano Ferri
**Topic:** workflow skill che, su invocazione manuale a fine coder, lancia il
reviewer, fa triage dei finding, li instrada agli agenti esistenti per il fix,
ri-revisiona e produce un recap decision-grade per ciclo.

---

## 1. Contesto e problema

Oltre a `reviewer` e `debugger`, serve automatizzare il *ciclo* trova-errore →
diagnostica → fix → ri-verifica, senza che l'utente debba ri-promptare a ogni
passo. Vincolo architetturale duro di Claude Code: **i sub-agent non spawnano
sub-agent** — quindi il reviewer non può invocare debugger/fixer; chi concatena
è sempre la sessione orchestratore. Capacità di fix già esistenti negli 8
agenti deployati: `debugger` (root-cause + fix minimo + regression + verifica),
`refactorer` (behavior-preserving, baseline verde), `coder` (plan-driven). Non
serve un agente nuovo: serve un **ruolo di orchestrazione** (skill).

## 2. Goal / Non-goal

**Goal:** una skill che in un'invocazione esegue un ciclo completo
review→triage→fix→re-review→recap e si ferma, lasciando all'utente la decisione
di ri-lanciare o committare.

**Non-goal:** nuovo agente "fixer"; chaining automatico senza gate umano;
commit/push dentro la skill; trigger via hook; esecuzione in parallelo dei fix;
sandboxing dei comandi (delegato al gate testcmd e a protect-files).

## 3. Architettura (Approccio A — skill pura, nessun agente nuovo)

- Skill/slash-command `review-triage-fix`, workflow markdown in
  `~/.claude/skills/review-triage-fix/`.
- Gira **nella sessione orchestratore**. Vincolo duro documentato nella skill:
  non invocabile da dentro un sub-agent (non potrebbe dispatchare).
- Riusa gli agenti esistenti `reviewer`, `debugger`, `refactorer`, `coder`.
  Nessuna modifica ai loro file di definizione.
- Nessun hook coinvolto: invocazione e decisione sono umane; gli hook restano
  per il gate deterministico (Stop-gate testcmd).

## 4. Invocazione e contratto un-ciclo

- Invocazione **manuale**, tipicamente dopo la fase coder; funziona ovunque ci
  siano modifiche recenti rilevabili dal reviewer.
- Un'invocazione = esattamente un ciclo:
  `reviewer → triage → route/fix (sequenziale) → re-review → recap → STOP`.
- L'utente decide se ri-invocare o committare. **Nessun commit dentro la
  skill** (azione HITL separata, coerente con CLAUDE.md globale).

## 5. Tassonomia di triage e routing

Sorgente: report del `reviewer` (BLOCKER/MAJOR/MINOR/NIT, `path:line`,
suggested-fix, verdetto).

| Classe finding | Destinazione | Note |
|---|---|---|
| Failure (errore runtime, test rosso, comportamento errato riproducibile) | `debugger` | root-cause + fix minimo + regression + verifica (già da contratto) |
| Strutturale (duplicazione, unità troppo grande, responsabilità ingarbugliate) | `refactorer` | richiede suite verde a baseline |
| Code-change localizzato non-failure non-strutturale (validazione mancante, edge-case test, naming, hardening piccolo) | `coder` | la skill sintetizza un **micro-piano** = finding + suggested-fix come piano a 1 voce, così il contratto plan-driven del coder è soddisfatto |
| Architetturale / design-level / ambiguo | nessuno | solo recap, flag per l'utente |
| Security BLOCKER (auth/secret/injection) | nessuno | circuit-breaker C |
| Finding a bassa confidence dichiarata dal reviewer | nessuno | agire su finding incerto è rischioso → solo segnalato |

NIT: instradati (coerente con "auto-route tutto") ma raggruppati come batch a
basso rischio e **separati nel recap** in sotto-tabella, così non annegano il
segnale.

## 6. Data flow del ciclo

1. **Pre-flight.** Verifica di girare nell'orchestratore; risolve project root;
   legge `<root>/.claude/test-cmd` come comando di verifica. Esegue il
   **baseline** una volta (verde/rosso/assente): serve per la rilevazione
   regressioni (§7-A) e per il refactorer (esige baseline verde).
2. **Review.** Dispatch `reviewer`. Edge gestiti: nessuna modifica → stop +
   recap "niente da fare"; diff enorme campionato → caveat propagato nel recap.
3. **Triage.** Parsa e classifica ogni finding per §5 → lista di routing
   (finding, classe, destinazione, micro-piano se coder).
4. **Fix sequenziale.** Per ogni finding routabile, in ordine di severità
   (BLOCKER → MAJOR → MINOR → NIT),
   dispatch dell'agente con input curato: finding + `path:line` +
   suggested-fix + (per coder) micro-piano + il `test-cmd` perché l'agente si
   auto-verifichi. **Mai in parallelo** (stesso codebase = conflitti di edit).
   Dopo ogni fix la skill **ri-esegue lei stessa il `test-cmd`** per cogliere
   subito una regressione.
5. **Re-review.** Dispatch `reviewer` sul nuovo stato → calcola il diff di
   ciclo (risolti / ancora aperti / nuovi / regrediti).
6. **Recap.** Costruisce header + tabella + diff + verdetto + flag. STOP.

## 7. Circuit breakers (attivi anche in auto-route-tutto)

- **A — Abort regressione.** Applicabile solo se baseline verde. Trigger
  autoritativo = la **ri-esecuzione di `test-cmd` fatta dalla skill** dopo il
  fix (§6 step 4), non l'auto-report dell'agente. Se passa verde→rosso e resta
  rosso dopo l'invocazione dell'agente responsabile: la skill smette di fixare,
  non impila, registra il fix colpevole, salta a re-review+recap con flag
  `ABORT: regressione a <finding>`.
  Se baseline già rosso: detection disattivata; recap segnala "baseline rosso —
  rilevazione regressioni non disponibile".
- **B — Hard-fail anti-test-weakening.** Dopo ogni fix, ispezione diff per:
  test cancellati, assert rimossi/allentati, skip/xfail aggiunti, test
  commentati (euristica su path di test + delta conteggio assert). Se scatta:
  finding marcato `NON RISOLTO — test indebolito` + flag BLOCKER nel recap,
  indipendentemente dal colore suite. **Nessun auto-revert** (azione
  distruttiva → resta al gate umano): il fix è lasciato in loco e segnalato
  forte.
- **C — Security BLOCKER report-only.** Finding BLOCKER su auth/secret/injection
  non entra mai nel fix loop; solo segnalato per decisione umana.
- **D — Non verificabile → UNVERIFIED.** Se manca `test-cmd` / vale `NONE` /
  niente framework: i fix avvengono ma ogni riga recap porta `UNVERIFIED`, A è
  inerte (no baseline), header recap `⚠ UNVERIFIED CYCLE`.

## 8. Formato recap

**Header:** project root; ciclo N; modalità verifica (`VERIFIED: test-cmd=…` o
`⚠ UNVERIFIED CYCLE`); colore baseline → colore post-ciclo; banner flag
prominente se presenti (`ABORT regressione`, BLOCKER anti-weakening, conteggio
security-BLOCKER deferiti).

**Tabella per-finding** — colonne:
`ID (sev+path:line+hash) | Sev | Problema (1 riga) | Routing
(debugger/refactorer/coder/REPORT-ONLY[reason]) | Change (file:line o "—") |
Verifica (PASS/FAIL/UNVERIFIED/N-A) | Stato vs ciclo prec.
(NEW/RESOLVED/STILL-OPEN/REGRESSED/WEAKENED)`.

**NIT:** sotto-tabella separata e compressa, sotto la principale.

**Diff di ciclo:** conteggi espliciti — Risolti N, Aperti N, Nuovi N,
Regrediti N — + una riga di lettura convergenza ("converge: 5→2 aperti" vs
"oscilla: A risolto, B nuovo rotto").

**Verdetto** (la skill raccomanda, decide l'utente): `SAFE: 0 aperti, suite
verde → valuta commit` / `RE-RUN consigliato: N aperti, converge` / `STOP &
ISPEZIONA: abort/weakening/non converge` / `UNVERIFIED: verifica manuale prima
del commit`.

## 9. Stato cross-ciclo

Artefatto **per-progetto, gitignored**: `<root>/.claude/.triage-fix-last.json`.
Contiene la lista finding del ciclo precedente (ID + stato) per calcolare il
diff NEW/RESOLVED/STILL-OPEN/REGRESSED. Project-scoped perché i finding sono
specifici del progetto; gitignored per non sporcare i commit. La skill aggiunge
`.triage-fix-last.json` a `.gitignore` se assente e il progetto è git.

## 10. Strategia di testing

Una skill di workflow non è unit-testabile come un hook. Superficie testabile =
le sotto-parti deterministiche: parser finding, classificatore triage, detector
anti-weakening, check regressione, builder recap, calcolo diff cross-ciclo.

- **Harness a scenari** su un progetto fixture con finding seminati di **tutte
  le classi di §5**: bug→test rosso (debugger), smell strutturale (refactorer),
  validazione mancante (coder), architetturale (report-only), security BLOCKER
  (report-only), low-confidence (report-only), NIT (batch): assert routing
  corretto, righe recap corrette,
  circuit breaker che scattano (fixture dove un "fix" cancella un test →
  WEAKENED; fixture dove un fix rompe un altro test → ABORT).
- L'orchestrazione LLM end-to-end è non-deterministica → si testa lo
  scaffolding deterministico con fixture; la pipeline completa si valida
  **manualmente una volta sul pilota** `~/developer/pricing-markup-cli` (come
  la Task 9 del testcmd).

## 11. Vincoli e invarianti

- Sub-agent non spawnano sub-agent → orchestrazione solo nella sessione
  principale.
- Nessun commit/push dentro la skill (HITL separato).
- Anti-test-weakening è già nei contratti di `debugger`/`coder`/`refactorer`;
  la skill lo **verifica** in più (difesa a strati, §7-B), non lo
  re-implementa.
- Verifica per-ciclo = il `.claude/test-cmd` del gate Stop testcmd già
  deployato (riuso, coerenza).
- Dispatch sequenziale obbligatorio (conflitti di edit).
- Skill autoconsistente e documentata per copia in altri repo (filosofia
  blueprint sez. 8).

## 12. Dipendenze

- Agenti esistenti deployati: `reviewer`, `debugger`, `refactorer`, `coder`
  (`~/.claude/agents/`).
- Skill `code-review-checklist` (tassonomia severità del reviewer).
- Gate Stop testcmd deployato (`<root>/.claude/test-cmd`,
  `~/.claude/hooks/stop-gate.sh`) — fonte del comando di verifica.

## 13. Criteri di successo

- Un'invocazione produce un recap decision-grade conforme a §8 e si ferma
  (nessun commit, nessuna iterazione automatica oltre il ciclo).
- Routing conforme a §5 su tutte le classi del fixture (incl. architetturale e
  low-confidence → report-only).
- I 4 circuit breaker scattano come da §7 nei rispettivi scenari fixture.
- Diff cross-ciclo corretto su due invocazioni consecutive.
- Validazione manuale end-to-end sul pilota: ciclo completo coerente col recap.

## 14. Out of scope

- Nuovo agente "fixer" (capacità già coperta da debugger/refactorer/coder).
- Trigger automatico / hook.
- Auto-revert dei fix (incluso il caso anti-weakening).
- Esecuzione parallela dei fix.
- Commit/PR (restano workflow HITL separati esistenti).
