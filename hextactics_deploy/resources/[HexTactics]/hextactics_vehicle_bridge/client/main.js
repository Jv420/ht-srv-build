'use strict';

const clampFuel = (value) => Math.max(0, Math.min(100, Number(value) || 0));
const lcFuelStarted = () => GetResourceState('lc_fuel') === 'started';

function getFuel(vehicle) {
  if (!vehicle || vehicle === 0 || !DoesEntityExist(vehicle)) return 0;
  if (lcFuelStarted()) {
    try { return clampFuel(global.exports.lc_fuel.GetFuel(vehicle)); }
    catch (error) { console.warn(`[hextactics_vehicle_bridge] LC Fuel GetFuel mislukt: ${error.message}`); }
  }
  return clampFuel(GetVehicleFuelLevel(vehicle));
}

function setFuel(vehicle, amount) {
  if (!vehicle || vehicle === 0 || !DoesEntityExist(vehicle)) return false;
  const fuel = clampFuel(amount);
  if (lcFuelStarted()) {
    try { global.exports.lc_fuel.SetFuel(vehicle, fuel); return true; }
    catch (error) { console.warn(`[hextactics_vehicle_bridge] LC Fuel SetFuel mislukt: ${error.message}`); }
  }
  SetVehicleFuelLevel(vehicle, fuel);
  return true;
}

exports('GetFuel', getFuel);
exports('SetFuel', setFuel);
exports('IsLcFuelActive', lcFuelStarted);
