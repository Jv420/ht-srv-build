# HexTactics Resources Clean v2.0.0

Deze map bevat de installatie-informatie voor de opgeschoonde resources-ZIP.

## Installatie
1. Maak een volledige back-up van je huidige `resources`-map en database.
2. Controleer of `resources/[libs]/oxmysql` bestaat. Ontbreekt die map, voer `install_oxmysql.bat` uit; dit haalt de officiële gratis release v2.14.1 op.
3. Importeer `database.sql`.
4. Bestond `ht_vehicle_registry` al door een eerdere Vehicle Suite-versie, dan mag je aanvullend `upgrade_existing_v2.sql` uitvoeren.
5. Importeer `optional_rdw_job.sql` alleen wanneer de job `rdw` nog niet bestaat.
6. Importeer `migrate_old_rdw.sql` alleen wanneer je oude `vehicle_registrations`-tabel bestaat en je die registraties wilt meenemen.
7. Neem de volgorde uit `server.cfg.snippet` over en verwijder oude `ensure`-regels uit `REMOVED_RESOURCES.txt`.
8. Lees `SECURITY_NOTES.md`: aangetroffen webhooks/tokens zijn uit deze build verwijderd en moeten bij de aanbieder worden ingetrokken.

## Nieuwe gratis, originele resources
- `ht_vehiclekeys`: openen/sluiten met **L**, sleutelmenu, sleutels delen en trackerzoeken.
- `ht_chopshop`: omkatgarage voor nieuw kenteken, VIN, sleutel, papieren en trackerbeheer.
- `ht_rdw`: registratie, tenaamstelling, APK, verzekering, boetes en kentekencontrole.
- `ht_customdealer`: eigen openbare autoverkoop en proefritten, los van de ESX-standaardlocatie.
- `esx_rdw`: kleine compatibiliteitsbrug naar `ht_rdw`; geen tweede RDW-systeem.

## Samenwerking met bestaande resources
- `ox_inventory` is de enige inventory; CityCentral is hierop ingesteld.
- `esx_garage` is de gekozen openbare garagebasis.
- `esx_vehicleshop` blijft alleen voor bestaande job/society-koppelingen. De openbare marker, blip en persoonlijke kentekenwissel zijn uitgeschakeld.
- Flitspalen, staffmenu, factuursancties en `hextactics_core` gebruiken hetzelfde `ht_vehicle_registry`.
- Het staffmenu zet een route naar `ht_customdealer` en gebruikt de centrale APK-, verzekering- en trackerstatus.

## Beveiliging
Gevoelige acties controleren server-side onder andere bronspeler, job, afstand, netwerkentity, voertuigmodel, kenteken, eigendom, items, saldo en rate limit. Bij tenaamstelling moeten de RDW-medewerker, huidige eigenaar en nieuwe eigenaar bij het voertuig staan. De nieuwe eigenaar moet binnen 30 seconden zelf met **Y** akkoord geven; **N** weigert de overdracht. Daarna worden eigendom, sleutels, papieren en betaling nogmaals server-side gecontroleerd en atomair verwerkt.

## Geen kopie van betaalde scripts
Er is geen betaalde of escrowcode ontsleuteld, gekopieerd of nagemaakt. Overlappende voertuigfuncties zijn vervangen door originele HexTactics-code. Niet-overlappende aangeleverde third-party resources zijn behouden; controleer hun gebruiks- en distributierecht in `LICENSE_NOTES.md`.

## Externe gratis kernresource
`oxmysql` ontbrak in de aangeleverde ZIP, terwijl veel resources hem vereisen. De meegeleverde Windows-installer downloadt de officiële release `v2.14.1` en plaatst die in `resources/[libs]/oxmysql`. De dependency zelf is niet opnieuw verpakt.
