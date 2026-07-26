# HexTactics Server Build

Publieke bronrepository voor de originele HexTactics FiveM-resources, database-installatie en txAdmin-deployment.

## Standaarddeploy

De complete normale installatie staat in [`hextactics_deploy`](./hextactics_deploy):

- `recipe.yml` voor txAdmin/Nitrado;
- `server.cfg` met correcte txAdmin-placeholders en startvolgorde;
- `resources/[HexTactics]` met de Vehicle Suite, NPC-roleplay en integratiebrug;
- `installer` met SQL, ox_inventory-items en LC Fuel-instructies.

## Crime Edition

De aparte installatie voor maximaal 20 spelers staat in [`hextactics_crime_deploy`](./hextactics_crime_deploy):

- beveiligde overvallen, loodsinbraken, ATM-kraak en smokkelroutes;
- voertuigboosting, hotwire, ECU-diefstal, kentekenklonen en de bestaande omkatgarage;
- gangs, territoria, zwarte markt, heler, witwassen en fictieve productieketens;
- politie-dispatch, forensisch bewijs, gevangeniswerk en ontsnappingspogingen;
- een eigen txAdmin-recept met ox_doorlock en bob74_ipl.

## Technische basis

- ESX Legacy
- oxmysql
- ox_lib
- ox_inventory
- ox_target
- LC Fuel als handmatig toe te voegen fuelsysteem
- Lua 5.4 voor serverscripts
- Moderne JavaScript-clients
- Server-side validatie voor gevoelige acties

## Belangrijk

Third-party scripts, MLO's, voertuigen, kleding en andere assets worden alleen opgenomen wanneer hun licentie openbare herdistributie toestaat. Betaalde of escrow-resources, waaronder LC Fuel, worden niet in deze publieke repository opgeslagen.
