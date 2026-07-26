# LC Fuel installeren op Nitrado

LC Fuel wordt niet in de publieke GitHub-repository opgenomen omdat het doorgaans een eigen Cfx/Tebex-asset is.

1. Download jouw legale LC Fuel-versie via de officiële aankoop/downloadlocatie.
2. Upload de map als `resources/[paid]/lc_fuel` of `resources/[standalone]/lc_fuel`.
3. Controleer dat de resourcenaam exact `lc_fuel` is.
4. Zet `ensure lc_fuel` **voor** `ensure hextactics_vehicle_bridge` in `server.cfg`.
5. Start geen `ox_fuel`, `LegacyFuel` of ander fuelsysteem tegelijk.
6. Voer na de serverstart `hextacticscheck` uit in de serverconsole.

De brug gebruikt:

```lua
exports.hextactics_vehicle_bridge:GetFuel(vehicle)
exports.hextactics_vehicle_bridge:SetFuel(vehicle, 75.0)
```

Een garage kan na het uitspawnen van een voertuig een sleutel geven via:

```lua
exports.hextactics_vehicle_bridge:GrantKeyToSource(source, plate, 'owner')
```
