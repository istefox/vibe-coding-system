# Modulo contesto Vibrofer (iniettabile)

Blocco pronto da inserire nella sezione contesto del prompt quando il tema riguarda Vibrofer. Va proposto, mai iniettato di nascosto. Scegli la versione nella lingua del prompt finale. Il blocco contiene SOLO informazioni pubbliche di posizionamento: mai aggiungere margini, listini interni, costi, sconti riservati o nomi di fornitori strategici.

## Versione italiana

```
<contesto_azienda>
Vibrofer Srl: azienda italiana specializzata in isolamento vibrazioni, smorzamento acustico e sistemi antivibranti industriali. Posizionamento tecnico-consulenziale B2B: non vende a catalogo, progetta soluzioni. Target: ingegneri e uffici tecnici industriali. Focus: soluzioni custom + service.
Catalogo: antivibranti a molla, in gomma e misti.
Norme ricorrenti: ISO 10816 (vibrazioni macchine), ISO 2631 (esposizione umana), UNI 9614 (edifici), EN 1299 (sorgenti), Direttiva Macchine 2006/42/CE.
Registro: tecnico-divulgativo per articoli e whitepaper, dati puri per contenuti aziendali, formale con "Lei" verso clienti. Clienti sempre anonimizzati nei contenuti pubblici salvo autorizzazione esplicita.
</contesto_azienda>
```

## Versione inglese

```
<company_context>
Vibrofer Srl: Italian company specializing in vibration isolation, acoustic damping, and industrial anti-vibration systems. B2B technical-consultancy positioning: engineered solutions, not catalog sales. Target audience: engineers and industrial technical departments. Focus: custom solutions + service.
Product range: spring, rubber, and hybrid anti-vibration mounts.
Recurring standards: ISO 10816 (machine vibration), ISO 2631 (human exposure), UNI 9614 (buildings), EN 1299 (vibration sources), Machinery Directive 2006/42/EC.
Register: technical-educational for articles and whitepapers, data-driven for corporate content, formal tone with clients. Client names always anonymized in public content unless explicitly authorized.
</company_context>
```

## Regole d'uso

- Proponi l'iniezione quando il prompt tocca: antivibranti, isolamento vibrazioni, acustica industriale, marketing o comunicazione Vibrofer, contenuti LinkedIn aziendali, email a clienti del settore.
- Il blocco entra nella sezione contesto dello scheletro (tag `<contesto>` per API, sezione "Contesto" per chat).
- Se l'utente fornisce contesto aziendale più specifico nel corso dell'intervista, quello prevale: il modulo è la base, non il tetto.
- Controllo finale obbligatorio: nessun dato sensibile (prezzi, margini, fornitori) deve comparire nel prompt consegnato, nemmeno se emerso durante l'intervista, senza conferma esplicita dell'utente.
