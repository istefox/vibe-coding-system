# Design — Path-case TOFU fix + leftover cleanup

**Data:** 2026-05-20
**Stato:** approvato → implementato (2026-05-20) — piano `docs/superpowers/plans/2026-05-20-path-case-tofu-fix.md`; live `stop-gate.sh`/`approve-test-cmd.sh` swapped a v3 content, `migrate-trust-paths.sh` deployato, trust file normalizzato 8→7 entry, `stop-gate.v2.sh` rimosso, harness `PASS=24 FAIL=0`
**Autore:** Adriano per Stefano Ferri
**Topic:** infra-fix in due sotto-fix indipendenti: (A1) normalizzazione case
del path nel meccanismo TOFU del Stop-gate testcmd su macOS case-insensitive
FS, (A2) cleanup del file staging `stop-gate.v2.sh` byte-identico al deployed.
Area "A" del brainstorm 2026-05-20 sulle migliorie all'automazione vibe.

---

## 1. Contesto e problema

### A1 — TOFU re-prompt falso su path case-variant

Il meccanismo TOFU del Stop-gate testcmd (deployato 2026-05-19, swarm-testcmd)
memorizza fiducia per progetto come `<sha256(test-cmd)>\t<project-root>` in
`~/.claude/state/stop-gate/trust`. `approve-test-cmd.sh` scrive la riga;
`stop-gate.sh` la cerca con `grep -F -x` (match esatto, byte-per-byte).

Su macOS la maggior parte dei volumi è case-insensitive di default (APFS /
HFS+). `/Users/stefanoferri/developer/X` e `/Users/stefanoferri/Developer/X`
puntano alla **stessa directory fisica** ma sono **stringhe diverse**. Né
`pwd` né `pwd -P` normalizzano la case: preservano la case tipata dall'utente
(o salvata in `$PWD`). Risultato: approvare da una shell con `~/developer`
non match-a un gate run con `~/Developer`, e viceversa → falso TOFU
re-prompt su comando già approvato.

Osservato in vivo il 2026-05-19 a fine pilot v1.1 di `review-triage-fix` su
`pricing-markup-cli`: il trust file contiene 3 entry duplicate per lo stesso
progetto (saved in memory `project_approve-testcmd-path-case.md`). Innocuo
(re-approvare risolve), ma frizione operativa reale e cruft accumulato.

### A2 — Leftover `stop-gate.v2.sh` byte-identico al deployed

Il piano swarm-testcmd ha sviluppato `~/.claude/hooks/stop-gate.v2.sh` come
file staging, swappato in `stop-gate.sh` al Task 8 finale (migration HITL).
Lo staging file è rimasto in `~/.claude/hooks/` come leftover. Pre-flight
verificato (cycle 3 brainstorm): `wc -c` mostra entrambi a 3724 byte; atteso
sha256 match. È cruft da rimuovere — confondibile come "due gate" diversi.

## 2. Goal / Non-goal

**Goal A1:** trust lookup case-invariant su macOS, mantenendo case-sensitive
su Linux/altri (dove case-variant ≠ stessa dir). Migrazione idempotente del
trust file esistente per rimuovere duplicati e portare tutte le entry nella
forma normalizzata. Trust file rimane human-readable per debugging.

**Goal A2:** rimozione sicura di `stop-gate.v2.sh` dopo prova formale di
byte-equality con il deployed `stop-gate.sh`. Backup pristine pre-delete.

**Non-goal A1:** supporto a volumi macOS APFS case-sensitive (rari, opt-in;
in quel caso il fix lowercasa correttamente come gli altri ma due dir
distinte differing-only-in-case verrebbero collassate in una trust entry —
trade-off accettato: macOS default è la maggioranza assoluta dei casi, e
chi sceglie case-sensitive APFS sa cosa fa).

**Non-goal A1:** schema-change del trust file (resta `<sha>\t<path>` per riga).

**Non-goal A2:** rimozione di altri file legacy (es. eventuali `.bak`); fuori
scope, manutenzione separata.

## 3. Architettura — Approccio 3 (`pwd -P` + lowercase su Darwin)

Decisione tra 3 approcci valutati (vedi brainstorm):

- **A. `realpath`/`pwd -P` puro** — risolve symlink (`/var`→`/private/var`)
  ma NON case (pwd preserva la case tipata). Fixa solo metà del bug.
- **B. `device:inode` come chiave** — identità FS vera, immune a qualunque
  variante string. Ma trust file diventa opaco (entry non più leggibili a
  occhio), e dir-rename invalida trust senza necessità reale (l'utente
  potrebbe legittimamente rinominare/spostare cartella mantenendo lo stesso
  test-cmd già approvato — caso d'uso scartato dal cambio schema).
- **C. `pwd -P` + lowercase su Darwin** ✓ — fixa entrambi i bug (case +
  symlink), trust file mantiene schema attuale, leggibile, debuggabile.
  Migrazione in-place (script una-tantum).

Scelto **C**. Trade-off accettato: volumi macOS case-sensitive (rari) hanno
collisioni potenziali (vedi non-goal). Approccio B teneva conto di quel caso
ma a costo di leggibilità e robustezza al rename — non vale per il
contesto reale d'uso (singolo utente, macOS default).

### Algoritmo di normalizzazione (deterministico, ~4 righe shell)

```bash
norm_path() {  # echoes the canonical trust path for $1 (a dir that exists)
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}
```

`STOP_GATE_UNAME` è un test-only env override (consistente con la famiglia
`STOP_GATE_STATE_DIR`/`STOP_GATE_TRUST_FILE`/`STOP_GATE_TEST_TIMEOUT` già
esistente): se settato, sostituisce l'output reale di `uname` per il check
piattaforma. In produzione resta unset → comportamento `uname` nativo.
Abilita il test #4 dell'harness senza PATH shim cross-platform.

Applicato:
- in `approve-test-cmd.sh` PRIMA dell'append al trust file
- in `stop-gate.sh` PRIMA del `grep -F -x`
- in `migrate-trust-paths.sh` per ogni entry esistente

Coerente per costruzione: storage e lookup usano la stessa funzione → match
garantito su qualunque case-variant la shell utente abbia passato.

**Duplicazione inline (decisione esplicita):** `norm_path` è copiata
byte-per-byte nei 3 script. Mirror della convenzione già stabilita nel
progetto, dove la funzione di upward-search della project-root è duplicata
in `stop-gate.sh:35-46` e `approve-test-cmd.sh:9-13`. Coupling via
`source` di un comune file richiederebbe gestione del path al sourcing,
aggiungerebbe un quarto file infrastrutturale, e renderebbe i hook
non-autoportabili (controvalore: lo stop-gate è progettato per essere
copiabile a sé stante). 4 righe duplicate × 3 = costo trascurabile.

## 4. Modifiche puntuali

### File modificati

- **`~/.claude/hooks/stop-gate.sh`** — dopo la risoluzione `ROOT=...; pwd ...`
  (intorno al blocco upward-search), applicare `norm_path` per ottenere il
  path canonicale usato nella riga di trust. Resto dello script invariato.
- **`~/.claude/hooks/approve-test-cmd.sh`** — stesso intervento: dopo aver
  risolto la project root via upward search, normalizzare prima di
  costruire `LINE=$(printf '%s\t%s' "$H" "$ROOT")`.
- **`~/.claude/hooks/tests/run-hook-tests.sh`** — nuovo blocco
  `# --- path-case A1 ---` con assert: (a) approve via `/X/dev/p` + lookup
  via `/X/DEV/p` → trust match (1 entry, gate allow); (b) migration script
  trasforma trust con duplicati case-variant in 1 entry lowercase; (c)
  idempotenza migration (seconda esecuzione non cambia nulla); (d)
  Linux-path simulato (mock `uname=Linux` via env): no-lowercase preservato.

### File nuovi

- **`~/.claude/hooks/migrate-trust-paths.sh`** — CLI standalone (NON hook).
  Legge `$STOP_GATE_TRUST_FILE` (default
  `~/.claude/state/stop-gate/trust`), per ogni riga: split su tab → sha + path;
  se il path è una dir esistente, `norm_path`-izza; emette `<sha>\t<norm>`;
  dedup (sort -u); riscrive atomico via `mv`. Idempotente: ri-esecuzione
  con trust già normalizzato è no-op (output bit-per-bit identico).
- **`~/.claude/state/backups/2026-05-20-path-case-fix/`** + `MANIFEST.md`
  pre-deploy backup di stop-gate.sh, approve-test-cmd.sh, trust file, e
  stop-gate.v2.sh (per A2).

### File rimossi (Task finale HITL-gated)

- **`~/.claude/hooks/stop-gate.v2.sh`** — dopo prova `sha256` byte-equality
  con `stop-gate.sh` deployato e backup pristine.

## 5. Migration & deploy

### Staging discipline

Implementazione in file **`.v3`** accanto ai live, NON sovrascrivendo
`stop-gate.sh`/`approve-test-cmd.sh` deployati fino al Task finale HITL:
- `~/.claude/hooks/stop-gate.v3.sh`
- `~/.claude/hooks/approve-test-cmd.v3.sh`

Harness exercita `.v3` via `STOP_GATE_SCRIPT`/path env per i test nuovi
(coerente con la disciplina del piano swarm-testcmd). Vita di
`stop-gate.v2.sh` continua intatta in produzione fino al swap finale.

### Task di migration (HITL gate)

1. **Backup pristine first** in `~/.claude/state/backups/2026-05-20-path-case-fix/`:
   `stop-gate.sh`, `approve-test-cmd.sh`, trust file, `stop-gate.v2.sh`, +
   `MANIFEST.md` con timestamp UTC e rollback instructions.
2. **Diff preview** (no write): `diff` deployed vs `.v3` per i due hook;
   `diff` trust file vs output normalizzato proposto da
   `migrate-trust-paths.sh --dry-run`.
3. **HITL gate**: presento (a) i due diff, (b) MANIFEST path, (c) rollback
   plan (restore 3 file dal backup + ri-eliminare v3/migrate); aspetto
   approvazione esplicita.
4. **Apply** (solo dopo approvazione):
   - `cp stop-gate.v3.sh stop-gate.sh && chmod +x`
   - `cp approve-test-cmd.v3.sh approve-test-cmd.sh && chmod +x`
   - `bash migrate-trust-paths.sh` (trasforma trust live)
5. **Validation reale**: ri-approva `pricing-markup-cli` via case opposta
   alla precedente; verifica `grep -c -F pricing-markup-cli trust` == 1 e
   che il prossimo Stop su una sessione attiva non triggeri TOFU re-prompt.
6. **A2 cleanup**: `shasum -a 256 stop-gate.sh stop-gate.v2.sh` → conferma
   match → `rm stop-gate.v2.sh`. Backup già preso in step 1.

### Rollback

`MANIFEST.md` documenta: ripristinare `stop-gate.sh`, `approve-test-cmd.sh`,
trust file dai backup; rimuovere `migrate-trust-paths.sh` + i `.v3` rimasti;
ri-creare `stop-gate.v2.sh` dal backup se A2 era già stato eseguito.
Massimo 5 comandi `cp` + 2 `rm`.

### Settings.json: NON tocca

I hook restano agli stessi path live. `settings.json` invariato.

## 6. Testing

Estensione del harness esistente `~/.claude/hooks/tests/run-hook-tests.sh`
con 4 nuovi check (cumulativo previsto: PASS attuale + 4):

| # | Caso | Asserzione |
|---|---|---|
| 1 | approve + lookup case-variant | `approve` con path `/X/dev/p`, lookup `stop-gate.v3.sh` con `cwd=/X/DEV/p` → exit 0, empty stdout (trust match, allow) |
| 2 | migration dedup case-variant | trust seed con 3 righe `<sha>\t/X/DEV/p`, `<sha>\t/X/dev/p`, `<sha>\t/x/dev/p` (stesso sha) → dopo `migrate-trust-paths.sh`: `grep -c . trust` = 1, contenuto lowercase |
| 3 | migration idempotenza | seconda invocazione su trust normalizzato → file bit-identico (diff = vuoto) |
| 4 | non-Darwin no-lowercase | `STOP_GATE_UNAME=Linux` (env override descritto in §3) + `norm_path "/X/Test/p"` → output preserva la case originale (no `tr`) |

**Bash 3.2.57 compat** (vincolo noto, memory `feedback_bash32-constraint.md`):
- `tr '[:upper:]' '[:lower:]'`: POSIX, funziona su bash 3.2 ✓
- `uname`: POSIX ✓
- niente assoc array, niente mapfile ✓

**Verifica indipendente del controller** dopo apply: il harness PASS deve
restare al nuovo totale; pricing-markup-cli re-approve manuale produce 1
entry trust; sessione fresca su pilot non triggera TOFU.

## 7. Vincoli & invarianti

- I hook (stop-gate.sh, approve-test-cmd.sh) restano **reporter conformi al
  contratto Stop**: stop-gate.sh esce 0 sempre (fail-open), spec §7 del
  piano swarm-testcmd; mai exit non-zero, mai blocco su errore interno
  (case-resolution failure → fail-open, NON re-prompt).
- Schema trust invariato (`<sha>\t<path>` per riga).
- Migration **idempotente** (test #3 dell'harness lo prova).
- Compat bash 3.2 mantenuta (no nuove dipendenze syntactic).
- Nessuna modifica a `settings.json` (i wire-up Stop/PreToolUse/etc.
  puntano agli stessi path live).

## 8. Out of scope

- A3 (MCP `google-workspace`, `microsoft-365` falliti) — separato, scelta utente.
- Supporto a volumi macOS case-sensitive (vedi non-goal §2).
- Schema-change del trust file (Approccio B scartato).
- Auto-cleanup di altri file `.bak`/legacy in `~/.claude/hooks/`.
- Cambio della convenzione di backup (`~/.claude/state/backups/<DATE>-<topic>/`)
  già stabilita da swarm-testcmd.

## 9. Confidence

**Alta** su A1: bug riproducibile, fix algoritmo ~3 righe shell, harness
deterministico isolato in `mktemp -d`, migration idempotente con test
dedicato. Trade-off case-sensitive APFS esplicito e accettato.

**Alta** su A2: prova formale `sha256` di byte-equality prima della delete;
backup pristine; rollback un-comando.

**Media** sul deploy: HITL gate obbligatorio (sovrascrittura di hook live);
mitigato da staging `.v3` + diff preview + manifest + rollback documentato.
Stessa disciplina del Task 8 swarm-testcmd, già eseguita con successo.
