# BRAINSTORM — Modalità anonimizzazione contributo strumento per repo pubblici

**Data:** 2026-05-23
**Fonte requisiti:** /Users/stefanoferri/Developer/vibe-coding-system/SPEC.md
**Tecniche applicate:** first-principles, assumption-busting, prior-art, alternative genuinamente diverse, inversione/pre-mortem

## Problema riformulato (first-principles)

Il bisogno irriducibile non è "cancellare la parola claude", ma **un repo pubblico indistinguibile da uno scritto a mano da un professionista**: qualità olistica (commit essenziali, doc concisi, zero file inutili) + assenza di qualunque marcatore dello strumento. La pulizia è un sottoinsieme della qualità, non il fine.

## Assunzioni sfidate

- **"Per ripulire serve sempre riscrivere la commit history"** — **CADUTA**. Vanno distinti 3 casi: (1) nuovi → commit puliti dall'inizio, zero rewrite; (2) esistenti non-ancora-pubblici → rewrite chirurgico pre-push; (3) esistenti già-pubblici → il rewrite richiede force-push (rompe cloni/fork, è visibile/sospetto) → meglio fresh-history publish.
- **"La detection deve essere lessicale (grep stringhe)"** — **DA VERIFICARE**. Il pattern è identico al secret-scanning; esistono strumenti maturi (gitleaks, git-filter-repo, BFG) → confronto delegato al researcher.
- **"Anonimo = niente claude"** — **CADUTA/ampliata**. First-principles sposta il target su "qualità indistinguibile", non solo rimozione di token.

## Alternative di approccio

### Alternativa A — Prevenzione (clean-by-construction)
- **Idea:** la modalità anonima nel chain produce output già conforme (commit/doc puliti dall'inizio); la skill fa solo audit di verifica.
- **Asse di differenza:** confine di responsabilità (prevenire vs rimediare).
- **Pro:** zero rewrite per i nuovi; pulizia "gratis". **Contro:** non copre i repo esistenti (Obsidian). **Costo:** basso.

### Alternativa B — Rimedio (scan + scrub on-demand)
- **Idea:** skill standalone che scansiona qualunque repo e rimedia (incluso history rewrite).
- **Asse di differenza:** deployment (standalone vs integrato nel chain).
- **Pro:** copre esistenti; disaccoppiato. **Contro:** i nuovi accumulano tracce da pulire ogni volta. **Costo:** medio.

### Alternativa C — Ibrido prevenzione+rimedio ★ (scelto)
- **Idea:** nuovi → modalità anonima nel chain (A); esistenti → skill clean-public-repo standalone (B).
- **Asse di differenza:** combinazione mirata allo scope (nuovi+retroattivo dello SPEC).
- **Pro:** copre tutto; ogni caso usa l'approccio giusto. **Contro:** due superfici da mantenere. **Costo:** medio.

### Alternativa D — Fresh-history publish ★ (scelto per i già-pubblici)
- **Idea:** per un repo già pubblico, non riscrivere la history ma pubblicare un repo pubblico **derivato** con pochi commit curati; la history di sviluppo (con tracce) resta privata.
- **Asse di differenza:** modello di deployment (mirror pubblico pulito vs stesso repo riscritto).
- **Pro:** niente force-push, niente buchi sospetti, niente rischio di corruzione del repo originale. **Contro:** si perde la granularità storica nel pubblico. **Costo:** basso-medio.

## Rischi emersi (inversione / pre-mortem)

- **[TOP] Rewrite distruttivo corrompe/perde un repo** → mitigazioni obbligatorie: backup branch/tag automatico + dry-run + conferma; e **preferire D (fresh-history) per i già-pubblici**, che evita del tutto il force-push sul repo originale. Il rewrite chirurgico in-place resta opzione di seconda scelta, mai default.
- Falsi positivi (dipendenze `claude-*`, "AI" in nomi) → rimozione solo-su-conferma protegge.
- Falso senso di sicurezza (traccia non rilevata in binari/metadati/file generati) → il report deve dichiarare esplicitamente la copertura e i limiti (cosa NON è stato scansionato).

## Idee adiacenti emerse

- **Secret-scanning bonus:** lo stesso scan può segnalare secret veri (pattern gitleaks) — utile ma *fuori scope ora*, annotato come future.
- **"Public mirror" riusabile:** il fresh-history publish è di fatto un workflow di pubblicazione mirror, potenzialmente utile a prescindere dall'anonimizzazione — future.

## Raccomandazione preliminare (NON vincolante, da validare dall'architect)

**Ibrido C** come architettura (prevenzione nei nuovi via modalità anonima nel chain + skill clean-public-repo per gli esistenti), con **D (fresh-history publish)** come strategia di default per i repo già pubblici e rewrite chirurgico solo come seconda scelta esplicita. Riuso di strumenti maturi (git-filter-repo/gitleaks) invece di un rewriter custom — **da confermare col researcher**. Priorità di sicurezza: backup + dry-run + conferma su ogni operazione distruttiva.

## Note per l'architect

- **Confronto strumenti (PRIORITARIO):** dispatch researcher per `git-filter-repo` vs `BFG` vs custom bash — affidabilità, dipendenze, idoneità al fresh-history vs rewrite chirurgico. (L'orchestrator lo lancia prima del dispatch architect.)
- **Dove innestare il gate** nella state machine del chain (Gate 0 esteso vs gate dedicato): da decidere nell'ADR.
- **Detection:** valutare riuso del pattern-set di gitleaks per le stringhe + set custom per i marcatori specifici dello strumento.
- **Requisito nuovo emerso (da riportare in SPEC se confermato):** il report di clean deve dichiarare la **copertura e i limiti** della scansione (cosa non è coperto: binari, metadati, file generati) per evitare il falso senso di sicurezza.
- Nome skill: `clean-public-repo` provvisorio; valutare se separare la parte "fresh-history publish" in una capability distinta.
