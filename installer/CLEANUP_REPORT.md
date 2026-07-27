# Opschoningsrapport

## Verwijderde conflicten
- `esx_inventory`: vervangen door `ox_inventory`.
- `idev_keys` en `p_vehiclekeys`: vervangen door `ht_vehiclekeys`.
- `MrNewbCustomPlates`, `NKHD-Plate-Switcher-V2`, `angelicxs-FREE-VINscratch` en `illu_plate`: vervangen door `ht_chopshop` en `ht_rdw`.
- `MrNewbPhoneTracker` en `tax_insurance_system`: vervangen door de tracker- en verzekeringsfuncties in de nieuwe suite.
- `esx_apk` en de oude inhoud van `esx_rdw`: vervangen door `ht_rdw`; de naam `esx_rdw` is nu alleen een compatibiliteitsbrug.
- `ls_usedvehicles`, `hextactics_vehiclemarket`: vervangen door `ht_customdealer`.
- `lunar_garage` en `zerodream_parking`: verwijderd zodat `esx_garage` de enige openbare garagebasis is.
- `progressBars`: verwijderd omdat `esx_progressbar` al aanwezig is.
- De kleinere dubbele `esx_economy` onder `[HexTactics]`: verwijderd; de uitgebreidere versie onder `[esx_addons]` blijft.

## Verwijderde verpakkingsfouten
- Volledige geneste kopieën van `esx_rdw`, `esx_vehicleshop`, `esx_joblisting`, `esx_lscustom`, `esx_policejob` en de Vinewood-PD-manifestkopie.
- Losse `ox_inventory.zip` en `vinewoodpd.zip` binnen de resources-map.
- Lege mappen `iak_DrugFarm` en `iak_ammunation`.

## Niet verwijderd
MLO's, kleding, politie, ambulance, brandweer en andere niet-overlappende gameplayresources zijn behouden. Deze taak controleert niet automatisch of iedere bestaande third-party resource commercieel of gratis is.

## Aanvullende correcties
- Dubbele `zipties`- en `car_battery`-definities in `ox_inventory/data/items.lua` zijn samengevoegd tot één geldige definitie per item.
- De foutieve trailing comma in `ox_inventory/locales/es.json` is verwijderd.
- De twee alternatieve Atlas Binco-themafolders zijn verwijderd; alleen de actieve basisresource blijft staan.
- Voor de ontbrekende gratis dependency `oxmysql` is een gecontroleerde installer toegevoegd.

## Centrale voertuig-integratie
- `CityCentral` gebruikt nu `ox_inventory` in plaats van de verwijderde ESX-inventory.
- `hextactics_adminmenu`, `hextactics_core`, `esx_speedcamera` en voertuiggebonden `esx_billing` gebruiken `ht_vehicle_registry`.
- De oude losse verzekering-, tracker- en registratie-tabellen van het staffmenu zijn verwijderd.
- `esx_vehicleshop` registreert bestaande jobvoertuigen via `ht_rdw`; zijn tweede register-SQL is verwijderd.
- Tenaamstelling vereist expliciete toestemming van de nieuwe eigenaar en wordt bij akkoord volledig opnieuw gevalideerd.
- Trackeronderdelen worden teruggegeven wanneer de database-update mislukt; geneste voertuigprops worden beperkt en geschoond.

## Geheimen opgeschoond
- Vijf ingevulde Discord-webhooks en één ingevuld Discord-bottoken zijn uit de deelbare build verwijderd.
- Zie `SECURITY_NOTES.md`; trek oude waarden in Discord in en maak alleen nieuwe secrets aan buiten de resources-ZIP.
- Ontwikkelmetadata `.github` en `.vscode` die niet door FXServer wordt gebruikt, is verwijderd.
