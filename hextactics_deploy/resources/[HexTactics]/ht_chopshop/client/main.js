'use strict';

const resourceName = GetCurrentResourceName();
const config = JSON.parse(LoadResourceFile(resourceName, 'config.json'));
const location = config.location;
let menuOpen = false;
let activeVehicle = 0;
let operationBusy = false;

function notify(message) {
  BeginTextCommandThefeedPost('STRING');
  AddTextComponentSubstringPlayerName(String(message));
  EndTextCommandThefeedPostTicker(false, false);
}

function normalizePlate(plate) {
  return String(plate || '').toUpperCase().replace(/\s+/g, '');
}

function drawText3D(x, y, z, text) {
  const [visible, sx, sy] = World3dToScreen2d(x, y, z);
  if (!visible) return;
  SetTextScale(0.32, 0.32);
  SetTextFont(4);
  SetTextProportional(true);
  SetTextCentre(true);
  SetTextColour(255, 255, 255, 225);
  SetTextOutline();
  BeginTextCommandDisplayText('STRING');
  AddTextComponentSubstringPlayerName(text);
  EndTextCommandDisplayText(sx, sy);
}

function getClosestVehicle(maxDistance = Number(config.vehicleDistance || 8.0)) {
  const [px, py, pz] = GetEntityCoords(PlayerPedId(), false);
  let closest = 0;
  let distanceFound = maxDistance + 0.001;
  for (const vehicle of GetGamePool('CVehicle')) {
    if (!DoesEntityExist(vehicle)) continue;
    const [x, y, z] = GetEntityCoords(vehicle, false);
    const distance = Math.hypot(px - x, py - y, pz - z);
    if (distance < distanceFound) {
      closest = vehicle;
      distanceFound = distance;
    }
  }
  return closest;
}

function getVehicleProps(vehicle) {
  const [color1, color2] = GetVehicleColours(vehicle);
  const [pearlescentColor, wheelColor] = GetVehicleExtraColours(vehicle);
  const [neonR, neonG, neonB] = GetVehicleNeonLightsColour(vehicle);
  const [smokeR, smokeG, smokeB] = GetVehicleTyreSmokeColor(vehicle);
  const props = {
    model: GetEntityModel(vehicle),
    plate: normalizePlate(GetVehicleNumberPlateText(vehicle)),
    plateIndex: GetVehicleNumberPlateTextIndex(vehicle),
    bodyHealth: GetVehicleBodyHealth(vehicle),
    engineHealth: GetVehicleEngineHealth(vehicle),
    tankHealth: GetVehiclePetrolTankHealth(vehicle),
    fuelLevel: GetVehicleFuelLevel(vehicle),
    dirtLevel: GetVehicleDirtLevel(vehicle),
    color1,
    color2,
    pearlescentColor,
    wheelColor,
    wheels: GetVehicleWheelType(vehicle),
    windowTint: GetVehicleWindowTint(vehicle),
    xenonColor: GetVehicleXenonLightsColor(vehicle),
    livery: GetVehicleLivery(vehicle),
    neonEnabled: [0, 1, 2, 3].map((index) => IsVehicleNeonLightEnabled(vehicle, index)),
    neonColor: [neonR, neonG, neonB],
    tyreSmokeColor: [smokeR, smokeG, smokeB],
    extras: {}
  };

  SetVehicleModKit(vehicle, 0);
  for (let i = 0; i <= 49; i += 1) props[`mod${i}`] = GetVehicleMod(vehicle, i);
  props.modTurbo = IsToggleModOn(vehicle, 18);
  props.modSmokeEnabled = IsToggleModOn(vehicle, 20);
  props.modXenon = IsToggleModOn(vehicle, 22);

  for (let extra = 0; extra <= 14; extra += 1) {
    if (DoesExtraExist(vehicle, extra)) props.extras[String(extra)] = IsVehicleExtraTurnedOn(vehicle, extra);
  }
  return props;
}

function openMenu(vehicle) {
  activeVehicle = vehicle;
  menuOpen = true;
  SetNuiFocus(true, true);
  SendNuiMessage(JSON.stringify({
    type: 'open',
    plate: normalizePlate(GetVehicleNumberPlateText(vehicle)),
    price: Number(config.price || 0)
  }));
}

function closeMenu() {
  menuOpen = false;
  SetNuiFocus(false, false);
  SendNuiMessage(JSON.stringify({ type: 'close' }));
}

async function progress(label, duration) {
  if (operationBusy) return false;
  operationBusy = true;
  const endAt = GetGameTimer() + duration;
  FreezeEntityPosition(PlayerPedId(), true);
  while (GetGameTimer() < endAt) {
    await new Promise((resolve) => setTimeout(resolve, 0));
    DisableAllControlActions(0);
    EnableControlAction(0, 200, true);
    const remaining = Math.ceil((endAt - GetGameTimer()) / 1000);
    drawText3D(location.x, location.y, location.z + 1.2, `${label} (${remaining}s)`);
    if (IsControlJustReleased(0, 200)) {
      FreezeEntityPosition(PlayerPedId(), false);
      operationBusy = false;
      notify('Handeling geannuleerd.');
      return false;
    }
  }
  FreezeEntityPosition(PlayerPedId(), false);
  operationBusy = false;
  return true;
}

RegisterNuiCallbackType('action');
on('__cfx_nui:action', async (data, cb) => {
  const action = String(data?.action || '');
  if (action === 'close') {
    closeMenu();
    cb({ ok: true });
    return;
  }

  if (!activeVehicle || !DoesEntityExist(activeVehicle)) {
    notify('Voertuig niet meer beschikbaar.');
    closeMenu();
    cb({ ok: false });
    return;
  }

  const netId = NetworkGetNetworkIdFromEntity(activeVehicle);

  if (action === 'reidentity') {
    closeMenu();
    const completed = await progress('VIN, kenteken en papieren vervangen', Number(config.operationDurationMs || 12000));
    if (completed && DoesEntityExist(activeVehicle)) {
      emitNet('ht_chopshop:server:reidentity', netId, getVehicleProps(activeVehicle));
    }
    cb({ ok: completed });
    return;
  }

  if (action === 'trackerAdd' || action === 'trackerRemove') {
    closeMenu();
    const completed = await progress(
      action === 'trackerAdd' ? 'Tracker monteren' : 'Tracker zoeken en verwijderen',
      Math.max(4000, Number(config.operationDurationMs || 12000) / 2)
    );
    if (completed) emitNet('ht_chopshop:server:tracker', netId, action === 'trackerAdd' ? 'add' : 'remove');
    cb({ ok: completed });
    return;
  }

  cb({ ok: false });
});

onNet('ht_chopshop:client:notify', (message) => notify(message));

onNet('ht_chopshop:client:reidentityResult', (netId, newPlate, vin) => {
  const vehicle = NetworkGetEntityFromNetworkId(Number(netId));
  if (vehicle && DoesEntityExist(vehicle)) {
    SetVehicleNumberPlateText(vehicle, String(newPlate).slice(0, 8));
    SetVehicleDoorsLocked(vehicle, 1);
    SetVehicleEngineOn(vehicle, false, true, true);
  }
  notify(`Omkatting afgerond: ${newPlate} | VIN ${vin}`);
});

setTick(() => {
  const ped = PlayerPedId();
  const [x, y, z] = GetEntityCoords(ped, false);
  const distance = Math.hypot(x - location.x, y - location.y, z - location.z);
  if (distance > Number(config.markerDistance || 25.0)) return;

  DrawMarker(
    1,
    location.x, location.y, location.z - 1.0,
    0, 0, 0,
    0, 0, 0,
    3.2, 3.2, 0.7,
    255, 255, 255, 120,
    false, false, 2, false, null, null, false
  );

  if (distance <= Number(config.interactDistance || 3.0)) {
    drawText3D(location.x, location.y, location.z + 0.55, '[E] Omkatgarage');
    if (IsControlJustReleased(0, 38) && !menuOpen && !operationBusy) {
      const vehicle = getClosestVehicle();
      if (!vehicle) {
        notify('Zet eerst een voertuig op de werkplaats.');
      } else {
        openMenu(vehicle);
      }
    }
  }
});
