# Beveiligingsmodel

- Alle prijzen, buit, cooldowns en vereiste politieaantallen staan server-side in `config.json` en worden opnieuw gecontroleerd bij voltooiing.
- Iedere activiteit krijgt een onvoorspelbare, kort geldige sessietoken die aan één speler, actie en locatie is gekoppeld.
- De server controleert startafstand, eindafstand, verstreken tijd, inventory-items, job, entitytype en kenteken.
- Voertuigacties accepteren alleen geldige OneSync-netwerkentities binnen bereik.
- Itemverwijdering vindt vóór beloning plaats; mislukte inventorytoevoegingen worden waar mogelijk teruggedraaid.
- Politie- en gevangeniscommando's controleren job of ACE-recht.
- Alle belangrijke acties worden in `ht_crime_audit` opgeslagen.
- Bewijs en gekloonde kentekens verlopen/worden opgeschoond.

De resource voorkomt veelvoorkomende client-eventmisbruik, maar vervangt geen goed serverbeheer, actuele artifacts, databaseback-ups en logcontrole.
