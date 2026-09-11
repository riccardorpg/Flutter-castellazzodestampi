# API Segnalazioni — Castellazzo de' Stampi

**Base URL produzione:** `https://www.castellazzodestampi.org/api`
**Base URL sviluppo:** `http://localhost/www.castellazzodestampi.org/public/api`

---

## Autenticazione

Tutte le API (tranne `/api/login`) richiedono l'header:

```
X-AUTH-TOKEN: <token>
```

Il token viene restituito dalla chiamata di login ed e' una stringa esadecimale di 64 caratteri.
Il token resta valido fino al logout o fino a un nuovo login (che lo rigenera).

### Risposte di errore standard

Tutte le risposte di errore seguono questo formato:

```json
{
  "success": false,
  "message": "Descrizione dell'errore"
}
```

| HTTP Status | Significato |
|-------------|-------------|
| 400 | Parametri mancanti o non validi |
| 401 | Non autenticato (token mancante/invalido) o credenziali errate |
| 403 | Account non attivo |
| 404 | Risorsa non trovata |

---

## 1. LOGIN

Autentica l'utente e restituisce un token API.

```
POST /api/login
Content-Type: application/json
```

**Body (JSON):**

```json
{
  "email": "utente@example.com",
  "password": "la-password"
}
```

**Risposta successo (200):**

```json
{
  "success": true,
  "token": "a1b2c3d4e5f6...64_caratteri_hex",
  "user": {
    "id": "1",
    "email": "utente@example.com",
    "name": "Mario",
    "surname": "Rossi",
    "role": "ROLE_STAFF",
    "permissions": {
      "segnalazioni": "rw",
      "reports": "rw"
    },
    "canEditReports": true,
    "canManageReports": false,
    "ignorePermission": false
  }
}
```

**Errori possibili:**
- 400 — `"Email e password sono obbligatori."`
- 401 — `"Credenziali non valide."`
- 403 — `"L'account non e' abilitato all'accesso."` (l'account non e' di tipo `ROLE_STAFF`)
- 403 — `"Account non attivo."` (password mai creata oppure account sospeso)
- 403 — `"L'account non ha il permesso di usare l'app delle segnalazioni."` (permesso *Invio segnalazioni (app)* non assegnato)

**Chi puo' accedere:** solo gli account staff attivi, non sospesi e con il permesso *Invio segnalazioni (app)* (almeno in lettura), assegnabile dall'area riservata in **Staff > scheda > Permessi**.

### I due permessi delle segnalazioni

Sul sito i permessi sono **due e separati**:

| Permesso | Slug | A cosa serve |
|----------|------|--------------|
| Invio segnalazioni (app) | `reports` | Usare l'app. E' il permesso che apre il login: **chi entra puo' sempre inserire e modificare le proprie** segnalazioni finche' sono in attesa. |
| Gestione segnalazioni | `reports_manage` | Lavorare le segnalazioni dall'area riservata del sito: stato, note, accorpamento delle analoghe, eliminazione, tipi di segnalazione. **Dall'app non si gestisce niente.** |

**Permesso dell'app:** `user.permissions.segnalazioni` (uguale a `permissions.reports`) vale `"rw"`, `"r"` oppure `""` (nessun permesso, ma in quel caso il login e' gia' stato rifiutato con 403).

Per l'app conta **solo se c'e' o non c'e'**: `"r"` e `"rw"` si comportano allo stesso modo, perche' l'app e' uno strumento da cittadino e chi ci entra segnala. La differenza fra i due valori resta valida sul sito, dove separa chi consulta da chi scrive. `canEditReports` e' il valore `"rw"` in forma booleana ed e' informativo per il sito, non per l'app.

**`canManageReports`** dice se l'account ha *Gestione segnalazioni*. **L'app non lo usa:** da li' ognuno vede e gestisce le proprie, chiunque sia. Il campo resta nel payload per il sito e per gli altri client. Il permesso di gestione **non** compare dentro `permissions`: lo slug `reports_manage` contiene `reports` e un'app che cerca il modulo per sottostringa lo confonderebbe con il permesso dell'app.

`ignorePermission` indica un account che bypassa il sistema dei permessi.

**Cosa e' modificabile:** ogni segnalazione porta i campi `is_owner` e `can_edit` (vedi paragrafo 5): sono quelli da guardare per decidere se mostrare Modifica ed Elimina su una singola scheda. Valgono solo le proprie, e solo finche' sono in attesa.

**Permessi cambiati mentre l'app e' aperta:** il blocco `user` viaggia anche con la lista delle segnalazioni (§ 5), non solo col login. Il client lo rilegge a ogni caricamento dell'elenco e si riallinea da solo, senza costringere l'utente a uscire e rientrare. Un permesso revocato riporta al login.

Gli stessi controlli valgono ad ogni chiamata autenticata: se l'account viene sospeso o perde il permesso, il token gia' emesso smette di funzionare e le API rispondono `401 "Non autenticato."`.

---

## 2. LOGOUT

Invalida il token corrente.

```
POST /api/logout
X-AUTH-TOKEN: <token>
```

**Body:** nessuno

**Risposta successo (200):**

```json
{
  "success": true,
  "message": "Logout effettuato."
}
```

---

## 3. MODIFICA PASSWORD

```
POST /api/modifica-password
Content-Type: application/json
X-AUTH-TOKEN: <token>
```

**Body (JSON):**

```json
{
  "current_password": "password-attuale",
  "new_password": "nuova-password"
}
```

**Risposta successo (200):**

```json
{
  "success": true,
  "message": "Password modificata con successo."
}
```

**Errori possibili:**
- 400 — `"Password attuale e nuova password sono obbligatorie."`
- 400 — `"La nuova password deve avere almeno 6 caratteri."`
- 400 — `"La password attuale non è corretta."`

---

## 4. TIPI SEGNALAZIONE

Restituisce l'elenco dei tipi di segnalazione attivi.

```
GET /api/tipi-segnalazione
X-AUTH-TOKEN: <token>
```

**Risposta successo (200):**

```json
{
  "success": true,
  "data": [
    {
      "id": "1",
      "name": "Buca stradale",
      "slug": "buca-stradale",
      "icon": "bi-exclamation-triangle"
    },
    {
      "id": "2",
      "name": "Illuminazione pubblica",
      "slug": "illuminazione-pubblica",
      "icon": "bi-lightbulb"
    }
  ]
}
```

**Campi:**

| Campo | Tipo | Descrizione |
|-------|------|-------------|
| `id` | string | ID del tipo |
| `name` | string | Nome visualizzato |
| `slug` | string | Slug URL-friendly |
| `icon` | string\|null | Nome icona Bootstrap Icons (es. `bi-exclamation-triangle`) |
| `icon_file` | string\|null | **URL assoluto** dell'icona custom (es. `https://www.castellazzodestampi.org/uploads/report_types/icon_abc123.png`) |

**Uso `icon_file` in Flutter:** se `icon_file` non è null, usarlo **direttamente** come URL immagine, senza anteporre la base URL; altrimenti usare `icon` come icona Bootstrap/Material.

---

## 5. SEGNALAZIONI (lista)

Segnalazioni ordinate per data decrescente, ognuna con la lista degli allegati.

**L'elenco contiene sempre e solo le segnalazioni inserite dall'utente autenticato**, qualunque sia il suo permesso — gestione compresa. Vedere le segnalazioni di tutti e' un lavoro da area riservata del sito, non dall'app.

La risposta porta anche il blocco **`user`**, identico a quello del login (§ 1). Serve al client per riallinearsi ai permessi correnti senza rifare l'accesso: l'elenco viene ricaricato all'apertura e a ogni refresh, quindi un permesso dato o tolto dal sito arriva da solo. Se `permissions.segnalazioni` torna vuoto, il client deve riportare al login.

```
GET /api/segnalazioni
X-AUTH-TOKEN: <token>
```

**Risposta successo (200):**

```json
{
  "success": true,
  "data": [
    {
      "id": "15",
      "type": {
        "id": "1",
        "name": "Buca stradale",
        "slug": "buca-stradale"
      },
      "datetime": "2026-03-15 10:30:00",
      "latitude": "45.4536700",
      "longitude": "9.0027400",
      "address": "Via Roma 15, Castellazzo de' Stampi",
      "priority": 0,
      "details": "Buca profonda circa 20cm sulla carreggiata...",
      "status": "pending",
      "status_label": "In attesa",
      "is_owner": true,
      "can_edit": true,
      "attachments": [
        {
          "file_name": "66a1b2c3d4e5f.jpg",
          "file_path": "https://www.castellazzodestampi.org/uploads/reports/15/66a1b2c3d4e5f.jpg",
          "thumb_path": "https://www.castellazzodestampi.org/uploads/reports/15/thumb_66a1b2c3d4e5f.jpg",
          "file_type": "image/jpg",
          "uploaded_at": "2026-03-15 10:30:15"
        }
      ]
    }
  ],
  "user": {
    "id": 3,
    "email": "mario.rossi@example.com",
    "name": "Mario",
    "surname": "Rossi",
    "role": "ROLE_STAFF",
    "permissions": { "segnalazioni": "rw", "reports": "rw" },
    "canEditReports": true,
    "canManageReports": false,
    "ignorePermission": false
  }
}
```

**Valori possibili per `status`:**

| status | status_label | Descrizione |
|--------|-------------|-------------|
| `in_creazione` | In creazione | Bozza salvata dall'app, non ancora inviata |
| `pending` | In attesa | Segnalazione appena inviata |
| `in_progress` | In lavorazione | Presa in carico dall'admin |
| `resolved` | Risolta | Problema risolto |
| `rejected` | Rifiutata | Segnalazione non valida |
| `merged` | Accorpata | **Stato storico**, non piu' assegnato. L'accorpamento non e' uno stato: e' una relazione fra segnalazioni che riguardano lo stesso problema, gestita solo dall'area riservata, e le segnalazioni accorpate conservano il loro stato di lavorazione (che si muove per tutto il gruppo insieme). L'app non ne sa e non ne deve sapere niente. |

**`is_owner` e `can_edit`:**

| Campo | Descrizione |
|-------|-------------|
| `is_owner` | la segnalazione e' stata inserita dall'utente autenticato |
| `can_edit` | l'utente puo' modificarla o eliminarla adesso: e' sua, ha `reports` in scrittura e lo stato e' `in_creazione` o `pending` |

`can_edit` e' l'unico campo da guardare per decidere se mostrare Modifica ed Elimina su una scheda. Diventa `false` da solo appena la segnalazione viene presa in carico (`in_progress`) o chiusa (`resolved`, `rejected`): da quel momento la lavora chi ha la gestione, dall'area riservata. Il server applica comunque la stessa regola e rifiuta le chiamate non ammesse.

---

## 6. DETTAGLIO SEGNALAZIONE

Restituisce il dettaglio di una segnalazione con gli allegati. Vale la stessa visibilita' della lista (§ 5): si apre **solo una propria segnalazione**, qualunque sia il permesso. Su quella di un altro la risposta e' `404 "Segnalazione non trovata."`.

```
GET /api/segnalazioni/{id}
X-AUTH-TOKEN: <token>
```

**Risposta successo (200):**

```json
{
  "success": true,
  "data": {
    "id": "15",
    "type": {
      "id": "1",
      "name": "Buca stradale",
      "slug": "buca-stradale"
    },
    "datetime": "2026-03-15 10:30:00",
    "latitude": "45.4536700",
    "longitude": "9.0027400",
    "address": "Via Roma 15, Castellazzo de' Stampi",
    "priority": 0,
    "details": "Buca profonda circa 20cm sulla carreggiata...",
    "status": "pending",
    "status_label": "In attesa",
    "attachments": [
      {
        "file_name": "66a1b2c3d4e5f.jpg",
        "file_path": "https://www.castellazzodestampi.org/uploads/reports/15/66a1b2c3d4e5f.jpg",
        "thumb_path": "https://www.castellazzodestampi.org/uploads/reports/15/thumb_66a1b2c3d4e5f.jpg",
        "file_type": "image/jpg",
        "uploaded_at": "2026-03-15 10:30:15"
      }
    ]
  }
}
```

**Campi allegato:**

| Campo | Tipo | Descrizione |
|-------|------|-------------|
| `file_name` | string | Nome del file su disco. E' il valore da mandare a § 9.1 per eliminare la foto |
| `file_path` | string | **URL assoluto** del file, gia' completo di schema e host |
| `thumb_path` | string | **URL assoluto** della miniatura 300px (gallery) |
| `file_type` | string | `image/jpg`, `image/png`, `file/pdf`, ecc. |
| `uploaded_at` | string | Data/ora upload (dal filesystem) |

**Note:**
- `file_path` e `thumb_path` sono URL gia' pronti: vanno usati **cosi' come sono**, senza anteporre la base URL del sito. Concatenarla produrrebbe un indirizzo doppio e l'immagine non si caricherebbe
  - Es: `https://www.castellazzodestampi.org/uploads/reports/15/66a1b2c3d4e5f.jpg`
  - Lo stesso vale per `type.icon_file` nei tipi di segnalazione (§ 4)
- Gli allegati sono gestiti via filesystem (cartella `/uploads/reports/{id}/`), non via database
- `attachments` e' presente sia nella lista che nel dettaglio; array vuoto `[]` se non ci sono file
- Per ogni immagine caricata viene generata una miniatura `thumb_<nome>` da 300px: usare
  `thumb_path` nelle gallery e `file_path` per la visualizzazione a schermo intero.
  Sulle immagini caricate prima di questa modifica `thumb_path` coincide con `file_path`
- Le immagini oltre 1 MB vengono ricompresse (lato max 1600px, qualita' 80) prima di essere archiviate

---

## 7. CREA SEGNALAZIONE

Crea una nuova segnalazione. Usa `multipart/form-data` per permettere l'upload di allegati.

```
POST /api/segnalazioni
Content-Type: multipart/form-data
X-AUTH-TOKEN: <token>
```

**Parametri form-data:**

| Campo | Tipo | Obbligatorio | Descrizione |
|-------|------|:------------:|-------------|
| `type_id` | string | Si | ID del tipo segnalazione (da `/api/tipi-segnalazione`) |
| `details` | string | No | Descrizione testuale della segnalazione |
| `latitude` | string | No | Latitudine GPS (es: `45.4536700`) |
| `longitude` | string | No | Longitudine GPS (es: `9.0027400`) |
| `address` | string | No | Indirizzo testuale |
| `status` | string | No | `pending` (default, invia) oppure `in_creazione` (salva come bozza) |
| `attachments[]` | file | No | Uno o piu' file allegati (foto, documenti) |

**Note importanti:**
- `latitude` e `longitude`: formato decimale con punto, precisione fino a 7 cifre decimali
- Le coordinate devono ricadere nel territorio del Comune di Corbetta, altrimenti la
  segnalazione viene rifiutata
- `attachments[]`: campo array — per inviare piu' file, ripetere il campo `attachments[]` per ciascun file
- La data/ora viene impostata automaticamente dal server al momento della creazione
- `status` accetta solo `pending` e `in_creazione`; qualsiasi altro valore viene ricondotto a `pending`
- La priority iniziale e' `0` (verra' calcolata successivamente dall'admin)

**Risposta successo (201):**

```json
{
  "success": true,
  "message": "Segnalazione inviata con successo.",
  "data": {
    "id": "16",
    "type": {
      "id": "1",
      "name": "Buca stradale",
      "slug": "buca-stradale"
    },
    "datetime": "2026-03-15 14:22:00",
    "latitude": "45.4536700",
    "longitude": "9.0027400",
    "address": "Via Roma 15, Castellazzo de' Stampi",
    "priority": 0,
    "details": "Buca profonda sulla carreggiata",
    "status": "pending",
    "status_label": "In attesa"
  }
}
```

**Errori possibili:**
- 403 — `"L'account ha le segnalazioni in sola lettura."` — controllo residuo: chi supera l'autenticazione ha sempre il permesso, quindi in pratica non si verifica
- 400 — `"Il tipo di segnalazione è obbligatorio."`
- 400 — `"Tipo di segnalazione non valido."`
- 400 — `"La posizione indicata non rientra nel territorio del Comune di Corbetta."`

---

## 8. MODIFICA SEGNALAZIONE

Modifica una segnalazione esistente. Solo le segnalazioni con status `in_creazione` o `pending` possono essere modificate dall'utente. Usa `multipart/form-data` per permettere l'aggiunta di nuovi allegati.

```
POST /api/segnalazioni/{id}
Content-Type: multipart/form-data
X-AUTH-TOKEN: <token>
```

**Parametri form-data (tutti opzionali — inviare solo i campi da modificare):**

| Campo | Tipo | Descrizione |
|-------|------|-------------|
| `type_id` | string | Nuovo ID tipo segnalazione |
| `details` | string | Nuova descrizione |
| `latitude` | string | Nuova latitudine |
| `longitude` | string | Nuova longitudine |
| `address` | string | Nuovo indirizzo |
| `status` | string | `in_creazione` (bozza) oppure `pending` (invia al Comune) |
| `attachments[]` | file | Nuovi file da aggiungere (non sostituisce i precedenti) |

**Risposta successo (200):**

```json
{
  "success": true,
  "message": "Segnalazione aggiornata.",
  "data": { ... }
}
```

**Errori possibili:**
- 403 — `"L'account ha le segnalazioni in sola lettura."` — controllo residuo: chi supera l'autenticazione ha sempre il permesso, quindi in pratica non si verifica
- 400 — `"Solo le bozze e le segnalazioni in attesa possono essere modificate."`
- 400 — `"La posizione indicata non rientra nel territorio del Comune di Corbetta."`
- 404 — `"Segnalazione non trovata."`

---

## 9. ELIMINA SEGNALAZIONE

Elimina una segnalazione e tutti i suoi allegati. Solo le segnalazioni con status `in_creazione` o `pending` possono essere eliminate dall'utente.

```
POST /api/segnalazioni/{id}/elimina
X-AUTH-TOKEN: <token>
```

**Body:** nessuno

**Risposta successo (200):**

```json
{
  "success": true,
  "message": "Segnalazione eliminata."
}
```

**Errori possibili:**
- 403 — `"L'account ha le segnalazioni in sola lettura."` — controllo residuo: chi supera l'autenticazione ha sempre il permesso, quindi in pratica non si verifica
- 400 — `"Solo le bozze e le segnalazioni in attesa possono essere eliminate."`
- 404 — `"Segnalazione non trovata."`

---

## 9.1 ELIMINA UNA FOTO GIA' CARICATA

Toglie un singolo allegato (foto o file) da una segnalazione, con la sua miniatura.

Serve alla modifica: aggiungendo allegati non si potevano piu' togliere, quindi uno
scatto sbagliato restava attaccato alla segnalazione per sempre.

```
POST /api/segnalazioni/{id}/allegati/elimina
X-AUTH-TOKEN: <token>
Content-Type: application/json
```

**Body (JSON):**

```json
{
  "file_name": "66a1b2c3d4e5f.jpg"
}
```

`file_name` e' il campo omonimo dell'allegato, come arriva in `attachments` (§ 5) — non
il percorso completo. Il server ne prende solo il nome del file, quindi un percorso
relativo non permette di uscire dalla cartella della segnalazione.

**Risposta successo (200):**

```json
{
  "success": true,
  "message": "Foto eliminata.",
  "data": { "...": "la segnalazione aggiornata, senza quell'allegato" }
}
```

`data` ha la stessa forma del dettaglio (§ 6): conviene usarla per riallineare la lista
delle foto invece di togliere l'elemento a mano.

**Errori possibili:**
- 401 — `"Non autenticato."`
- 403 — `"L'account ha le segnalazioni in sola lettura."` — controllo residuo: chi supera l'autenticazione ha sempre il permesso, quindi in pratica non si verifica
- 400 — `"La segnalazione e' stata presa in carico: le foto non si possono piu' togliere."`
- 404 — `"Segnalazione non trovata."` (inesistente oppure di un altro utente)
- 404 — `"Allegato non trovato."`

**Attenzione:** l'eliminazione e' immediata e definitiva, non aspetta il salvataggio
della segnalazione. Va chiesta conferma all'utente.

---

## 10. GEOCODING (solo Corbetta)

Entrambi gli endpoint sono vincolati al territorio del Comune di Corbetta: l'app li usa
per compilare il campo indirizzo con coordinate valide.

### 10.1 Autocomplete indirizzo

```
GET /api/autocomplete-indirizzo?q=via+roma
X-AUTH-TOKEN: <token>
```

Restituisce al massimo 5 risultati, tutti nel Comune di Corbetta (array vuoto se
la query e' piu' corta di 3 caratteri o non ci sono corrispondenze).

```json
{
  "success": true,
  "data": [
    { "display_name": "Via Roma, Corbetta, Milano, Lombardia, Italia", "lat": "45.4674", "lon": "8.9174" }
  ]
}
```

### 10.2 Reverse geocoding

```
GET /api/reverse-geocode?lat=45.4674&lon=8.9174
X-AUTH-TOKEN: <token>
```

```json
{
  "success": true,
  "data": {
    "address": "Via Roma 12, Corbetta",
    "in_corbetta": true
  }
}
```

`in_corbetta` a `false` indica che la posizione e' fuori dal territorio comunale:
l'app deve impedire l'invio della segnalazione.

**Errori possibili:**
- 400 — `"Parametri lat e lon obbligatori."`
- 401 — `"Non autenticato."`

---

## Riepilogo endpoint

| Metodo | Endpoint | Auth | Content-Type | Descrizione |
|--------|----------|:----:|-------------|-------------|
| POST | `/api/login` | No | `application/json` | Login |
| POST | `/api/logout` | Si | — | Logout |
| POST | `/api/modifica-password` | Si | `application/json` | Cambio password |
| GET | `/api/tipi-segnalazione` | Si | — | Lista tipi segnalazione |
| GET | `/api/segnalazioni` | Si | — | Elenco delle proprie segnalazioni (+ blocco `user`) |
| GET | `/api/segnalazioni/{id}` | Si | — | Dettaglio segnalazione |
| POST | `/api/segnalazioni` | Si | `multipart/form-data` | Crea segnalazione |
| POST | `/api/segnalazioni/{id}` | Si | `multipart/form-data` | Modifica segnalazione |
| POST | `/api/segnalazioni/{id}/allegati/elimina` | Si | `application/json` | Elimina una foto gia' caricata |
| POST | `/api/segnalazioni/{id}/elimina` | Si | — | Elimina segnalazione |
| GET | `/api/autocomplete-indirizzo` | Si | — | Ricerca indirizzi (solo Corbetta) |
| GET | `/api/reverse-geocode` | Si | — | Coordinate -> indirizzo (+ `in_corbetta`) |

---

## Note per lo sviluppo app

1. **Persistenza token**: salvare il token in secure storage (Keychain iOS / EncryptedSharedPreferences Android) dopo il login
2. **Gestione sessione**: se una risposta restituisce 401, riportare l'utente alla schermata di login
3. **GPS**: al momento della creazione, l'app dovrebbe richiedere i permessi di geolocalizzazione e inviare `latitude`, `longitude` e possibilmente l'`address` ottenuto via reverse geocoding
4. **Upload foto**: l'app dovrebbe permettere di scattare una foto dalla fotocamera o selezionarla dalla galleria, e inviarla come `attachments[]` nel form-data
5. **Modifica/Elimina**: mostrare i pulsanti modifica/elimina solo dove `can_edit` e' `true`. Il permesso globale non basta: una segnalazione presa in carico non si tocca piu' dall'app, si lavora dall'area riservata
6. **Allegati in modifica**: i nuovi allegati si aggiungono, non sostituiscono quelli esistenti; per togliere una foto gia' caricata serve `POST /api/segnalazioni/{id}/allegati/elimina` (§ 9.1)
7. **URL allegati e icone**: `file_path`, `thumb_path` e `icon_file` sono gia' URL assoluti. Vanno usati cosi' come sono: anteporre la base URL del sito produce un indirizzo doppio e l'immagine non si carica
