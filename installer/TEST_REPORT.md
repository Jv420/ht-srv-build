# Statisch testverslag — HexTactics Resources Clean v2.0.0

## Uitgevoerde controles
- De aangeleverde ZIP is uitgepakt en als aparte schone build verwerkt; het origineel is niet overschreven.
- 133 top-level FiveM-resources zijn geïnventariseerd.
- Alle top-level resources hebben een `fxmanifest.lua` of legacy `__resource.lua`.
- Geneste resource-manifests en ingesloten ZIP/RAR/7z-archieven zijn gecontroleerd.
- 322 strikte JSON-bestanden zijn geparseerd; 9 `tsconfig`-bestanden met toegestane JSONC zijn apart overgeslagen.
- 8 JavaScript-bestanden van de vier nieuwe resources zijn met Node.js `--check` gecontroleerd.
- 213 `ox_inventory`-items zijn gevonden en alle 213 sleutels zijn uniek.
- De vereiste voertuigitems zijn ieder precies één keer aanwezig.
- De nieuwe resourceafhankelijkheden, centrale tabelnamen, uitgeschakelde standaarddealer en verwijderde conflictscripts zijn statisch gecontroleerd.
- 15 nieuwe/gewijzigde Lua-bestanden zijn aanvullend met de Lua 5.4-loader syntactisch gecontroleerd.

## Resultaat
- Blokkerende auditfouten: **0**.
- Verwachte waarschuwingen: **4** — iedere nieuwe voertuigresource vereist `oxmysql`, dat bewust niet is meeverpakt. De officiële installer is wel aanwezig.

## Beveiligingscontroles in de code
- Server-side rate limiting en permissie/jobcontroles.
- Netwerk-ID naar bestaande voertuigentity valideren.
- Server-side afstands-, eigendoms-, model-, kenteken-, saldo- en itemcontrole.
- Database-transacties en terugbetaling/teruggave bij mislukte gevoelige acties.
- Tenaamstelling met aanwezigheid van beide eigenaren, een eenmalig token, 30 seconden vervaltijd, expliciet akkoord en volledige hercontrole.

## Niet uitvoerbaar in deze omgeving
Er is geen echte FXServer, OneSync-sessie, ESX-spelerdata of MariaDB-gameomgeving gestart. Daardoor zijn daadwerkelijke spawning, NUI-bediening, statebagreplicatie, inventorymetadata en SQL-migraties niet end-to-end in-game getest. Test daarom eerst op een stagingserver met een databaseback-up en één testvoertuig.
