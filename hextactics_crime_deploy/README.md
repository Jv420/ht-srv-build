# Delfzijl | HexTactics Crime Edition

Een aparte txAdmin/Nitrado-deploy voor maximaal 20 spelers. De editie gebruikt één modulaire Crime Suite in plaats van honderden overlappende resources.

## Ingebouwde systemen

- Kassa- en winkelkluisovervallen
- ATM-kraak
- Loods- en containerinbraken
- Dynamische smokkelroutes
- NPC-/straatverkoop met server-side prijzen
- Fictieve cannabis-, importwaar- en synthetische productieketen
- Zwarte markt, heler, gemarkeerde-biljettenwissel en witwassen
- Voertuig hotwire, ECU-diefstal, tracker verwijderen en kentekenklonen
- Boostcontracten en koppeling met de bestaande HexTactics Vehicle Suite
- Gangs, uitnodigingen, territoria en reputatie
- Heat, cooldowns, politieaantallen en dispatchmeldingen
- Forensisch bewijs met bewijszakken
- Gevangenis, werkstraf, strafvermindering en ontsnappingspoging
- NUI Crime-menu op F6

## Open-source dependencies

Het recipe installeert alleen duidelijk gelicentieerde upstreamresources:

- ESX Legacy
- oxmysql, ox_lib, ox_target, ox_inventory
- ox_doorlock (GPL-3.0)
- bob74_ipl (MIT)

LC Fuel wordt niet herverdeeld. Upload jouw rechtmatige resource handmatig.

## Commands

- `/crime` of F6
- `/hotwire`
- `/plateclone`
- `/trackerremove`
- `/stealecu`
- `/boost`
- `/streetsell weed_bag`
- `/ganginvite [id]`
- `/gangleave`
- `/crimecraft [recept]`
- Politie: `/crimekit`, `/crimeevidence`, `/collectevidence [id]`, `/crimeprofile [id]`, `/crimejail [id] [minuten] [reden]`, `/crimeunjail [id]`

## Beveiliging

De client bepaalt nooit een beloning, prijs, politieaantal, cooldown, itemverbruik of geldige locatie. Iedere actie krijgt een korte server-side sessietoken en wordt bij starten én voltooien gecontroleerd op afstand, verstreken tijd, items, job, entity en database-uitkomst.
