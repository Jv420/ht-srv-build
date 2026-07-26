# HexTactics Deploy

Complete vrije deploymap voor **Delfzijl | HexTactics** op ESX Legacy.

## Inhoud

- `ht_vehiclekeys`: servergevalideerde voertuigkeys en trackers.
- `ht_rdw`: kenteken, VIN, tenaamstelling, APK, verzekering, belastingstatus, gestolenstatus en voertuighistorie.
- `ht_chopshop`: omkatten met nieuw kenteken/VIN, documenten, onderdelen en trackerwerk.
- `ht_customdealer`: eigen beveiligde autodealer met servercatalogus.
- `hextactics_npc_roleplay`: ALT+E-politiecontroles op game-NPC's, boetes, signaleringen, fouilleren en arresteren.
- `hextactics_vehicle_bridge`: koppeling voor LC Fuel, garages, keys en RDW-data.
- `hextactics_startup_check`: controle op ontbrekende of botsende resources.
- `recipe.yml`: installatie via txAdmin Server Deployer.

## Belangrijk

De publieke recipe installeert de vrije onderdelen: Cfx-defaultresources, ESX Legacy, oxmysql, ox_lib, ox_inventory, ox_target en de HexTactics-resources. LC Fuel moet handmatig worden geüpload omdat een eigen/escrow-asset niet vanuit een publieke GitHub-repository mag worden herverdeeld.

## txAdmin-installatie

1. Open txAdmin op je Nitrado-server.
2. Kies **Deployer** en daarna **Remote URL Template**.
3. Plak de raw URL van `hextactics_deploy/recipe.yml`.
4. Vul de databasegegevens, Cfx-licensekey, servernaam en slots in.
5. Laat het recept volledig uitvoeren.
6. Upload daarna LC Fuel en activeer `ensure lc_fuel` vóór `hextactics_vehicle_bridge`.
7. Start de server en voer `hextacticscheck` uit in de console.

## Bestaande server

Gebruik het recept niet over een bestaande productie-installatie zonder back-up. Kopieer bij een bestaande server alleen `resources/[HexTactics]`, importeer `installer/database.sql`, voeg de inventory-items toe en neem de startvolgorde uit `server.cfg` over.

## Beveiliging

Gevoelige events valideren server-side onder meer speleridentiteit, job/rang, positie, entity-netwerk-ID, afstand, eigendom, kenteken, catalogusprijzen, saldo, inventory-items, cooldowns en database-uitkomsten. Clients bepalen geen aankoopprijs, VIN, kenteken, boetebedrag of eigendomsoverdracht.

## Commando's

- `/autosleutels` – sleutelmenu.
- `/npccontrole` – alternatief voor ALT+E bij een NPC.
- `hextacticscheck` – serverconsolecontrole; ingame alleen met ACE `hextactics.admin`.

## Licentie

De originele HexTactics-code in deze map valt onder de MIT-licentie. Externe dependencies worden tijdens installatie uit hun officiële openbare bronnen gedownload en behouden hun eigen licentie.
