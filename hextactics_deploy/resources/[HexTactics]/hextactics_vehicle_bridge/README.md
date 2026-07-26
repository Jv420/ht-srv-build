# hextactics_vehicle_bridge

Centrale integratie voor garages en andere voertuigresources.

## Clientexports

```lua
local fuel = exports.hextactics_vehicle_bridge:GetFuel(vehicle)
exports.hextactics_vehicle_bridge:SetFuel(vehicle, 75.0)
```

## Serverexports

```lua
exports.hextactics_vehicle_bridge:GrantKeyToSource(source, plate, 'owner')
local record = exports.hextactics_vehicle_bridge:GetVehicleRecord(plate)
```

LC Fuel is een eigen/escrow-resource en wordt daarom niet vanuit de publieke recipe gedownload. Wanneer `lc_fuel` niet gestart is, gebruikt de brug tijdelijk de standaard GTA-brandstofnative.
