# Patch priorità segnalazioni (da applicare sul progetto Symfony)

## La regola

La priorità non si chiede all'utente: **la porta la categoria**. Una
segnalazione prende automaticamente la priorità impostata sul suo tipo in
`/amministratore/tipi-segnalazione/` (colonna `priority` di
`cas_report_type`).

Oggi non accade: `ApiController::createReport()` forza `setPriority(0)`,
ignorando il tipo. Per questo "rifiuti" ha priorità 1 fra i tipi, ma la
segnalazione rifiuti arriva a 0 in `/amministratore/segnalazioni/`.

## Come applicarla

Il file **`ApiController_DA_CARICARE.php`** in questa cartella è già la
versione corretta: va caricato sul server al posto di

    src/Controller/Api/ApiController.php

(poi `php bin/console cache:clear`). `ApiController.php` in questa repo è
rimasto la copia di riferimento non modificata; il diff fra i due è
esattamente quello descritto qui sotto.

Finché sul server non arriva questa modifica il pannello continuerà a
mostrare 0 e a farti correggere la priorità a mano: la scrive l'API, non
l'app.

---

Le modifiche, se preferisci applicarle a mano:

## 1. `createReport()` — la categoria assegna la priorità

Sostituire:

```php
        $report->setStatus('pending');
        $report->setPriority(0);
```

con:

```php
        $report->setStatus('pending');
        $report->setPriority($this->typePriority($em, $reportType));
```

## 2. `updateReport()` — se cambia la categoria, cambia la priorità

Se l'utente modifica una segnalazione in attesa e ne cambia il tipo, la
priorità deve seguire il tipo nuovo, altrimenti resta quella del vecchio.

Sostituire:

```php
        if ($typeId) {
            $reportType = $em->getRepository(ReportType::class)->find($typeId);
            if ($reportType) {
                $report->setReportType($reportType);
            }
        }
```

con:

```php
        if ($typeId) {
            $reportType = $em->getRepository(ReportType::class)->find($typeId);
            if ($reportType) {
                $report->setReportType($reportType);
                $report->setPriority($this->typePriority($em, $reportType));
            }
        }
```

## 3. L'helper da aggiungere alla classe

```php
    /**
     * La priorità di una segnalazione è quella della sua categoria: qui si
     * legge tale e quale dalla colonna `priority` di cas_report_type, la
     * stessa gestita dal pannello amministratore. Via SQL come fa già
     * l'endpoint /tipi-segnalazione; se l'entity ReportType mappa il campo
     * basta $reportType->getPriority().
     */
    private function typePriority($em, ReportType $reportType)
    {
        return $em->getConnection()->fetchOne(
            'SELECT priority FROM cas_report_type WHERE id = ?',
            [$reportType->getId()]
        );
    }
```

---

## Backfill delle segnalazioni già a zero

Le segnalazioni già inviate restano a 0: questa query dà a ciascuna la
priorità della sua categoria.

```sql
UPDATE cas_report r
  JOIN cas_report_type t ON t.id = r.report_type_id
   SET r.priority = t.priority
 WHERE r.priority = 0;
```

Nome tabella da confermare: qui è `cas_report`, coerente con
`cas_report_type`, ma il dump `segnalazioni_demo.sql` usa `report`.

## Un controllo sui tipi di colonna

Se `cas_report_type.priority` è testuale ("alta"/"media"/…) anche
`cas_report.priority` deve accettare testo, altrimenti la copia va in errore
o tronca. Se sono entrambe intere — come sembra, dato che "rifiuti" porta 1 —
non c'è nulla da fare.

## Lato app

Nessuna modifica: la priorità viene assegnata e gestita solo lato
amministratore, l'app non la manda e non la mostra.
