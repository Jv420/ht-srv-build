# Installatie op Nitrado / txAdmin

1. Maak in Nitrado een nieuwe, lege FiveM-server aan voor maximaal 20 spelers.
2. Open txAdmin en kies **Popular Recipes** → **Remote URL Template**.
3. Plak de raw URL van `hextactics_crime_deploy/recipe.yml`.
4. Vul de Cfx-licensekey en databasegegevens in en laat het recept afronden.
5. Upload daarna jouw rechtmatige `lc_fuel`-map naar `resources/[standalone]/lc_fuel`.
6. Haal in `server.cfg` het hekje voor `ensure lc_fuel` weg.
7. Zet `ensure lc_fuel` vóór `ensure hextactics_vehicle_bridge`.
8. Start de server en voer `hextacticscheck` uit in de serverconsole.

## Eerste test

- F6 opent het Crime-menu.
- Test een kassa met minimaal één politieagent online.
- Test `/hotwire` op een NPC-voertuig.
- Test `/boost` met een wegwerptelefoon en minimaal reputatie 10.
- Test de zwarte markt uitsluitend op de actieve marktlocatie.
- Test `/crimejail` met een politiejob of admin ACE.
- Controleer `ht_crime_audit` en `ht_crime_evidence` in de database.

## Niet tegelijk starten

Start geen tweede inventory, target, voertuigsleutel-, chopshop-, gang-, prison- of robberyresource die dezelfde functie overneemt. Dubbele systemen veroorzaken dubbele beloningen, verschillende kentekens en eventconflicten.

## Eerste politietest

Gebruik `/crimekit` om bewijszakken en handschoenen op te halen. Gebruik daarna `/crimeevidence` en `/collectevidence [id]`.
