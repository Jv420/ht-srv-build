'use strict';

const resourceName = GetCurrentResourceName();
const config = JSON.parse(LoadResourceFile(resourceName, 'config.json'));
const location = config.location;
const spawn = config.spawn;
let menuOpen = false;
let testVehicle = 0;
let testDriveToken = 0;

function notify(message) {
  BeginTextCommandThefeedPost('STRING');
  AddTextComponentSubstringPlayerName(String(message));
  EndTextCommandThefeedPostTicker(false, false);
}

function drawText3D(x, y, z, text) {
  const [visible, sx, sy] = World3dToScreen2d(x, y, z);
  if (!visible) return;
  SetTextScale(0.32, 0.32);
  SetTextFont(4);
  SetTextCentre(true);
  SetTextColour(255, 255, 255, 225);
  SetTextOutline();
  BeginTextCommandDisplayText('STRING');
  AddTextComponentSubstringPlayerName(text);
  EndTextCommandDisplayText(sx, sy);
}

function openMenu() {
  menuOpen = true;
  SetNuiFocus(true, true);
  SendNuiMessage(JSON.stringify({ type: 'open', vehicles: config.vehicles || [] }));
}

function closeMenu() {
  menuOpen = false;
  SetNuiFocus(false, false);
  SendNuiMessage(JSON.stringify({ type: 'close' }));
}

async function loadModel(modelName) {
  const hash = GetHashKey(modelName);
  if (!IsModelInCdimage(hash) || !IsModelAVehicle(hash)) return 0;
  RequestModel(hash);
  const timeout = GetGameTimer() + 10000;
  while (!HasModelLoaded(hash) && GetGameTimer() < timeout) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  return HasModelLoaded(hash) ? hash : 0;
}

function deleteTestVehicle() {
  if (testVehicle && DoesEntityExist(testVehicle)) {
    SetEntityAsMissionEntity(testVehicle, true, true);
    DeleteVehicle(testVehicle);
  }
  testVehicle = 0;
}

async function startTestDrive(modelName) {
  if (testVehicle && DoesEntityExist(testVehicle)) {
    notify('Je hebt al een actieve proefrit.');
    return;
  }

  const allowed = (config.vehicles || []).some((vehicle) => vehicle.model === modelName);
  if (!allowed) return;

  const hash = await loadModel(modelName);
  if (!hash) {
    notify('Voertuigmodel kon niet worden geladen.');
    return;
  }

  testVehicle = CreateVehicle(
    hash,
    Number(spawn.x), Number(spawn.y), Number(spawn.z),
    Number(spawn.heading || 0),
    true,
    true
  );
  SetEntityAsMissionEntity(testVehicle, true, true);
  SetVehicleNumberPlateText(testVehicle, 'PROEFRIT');
  SetVehicleFuelLevel(testVehicle, 100.0);
  SetVehicleDoorsLocked(testVehicle, 1);
  TaskWarpPedIntoVehicle(PlayerPedId(), testVehicle, -1);
  SetModelAsNoLongerNeeded(hash);

  testDriveToken += 1;
  const token = testDriveToken;
  const seconds = Math.max(15, Number(config.testDriveSeconds || 60));
  notify(`Proefrit gestart voor ${seconds} seconden.`);

  setTimeout(() => {
    if (token !== testDriveToken) return;
    deleteTestVehicle();
    notify('De proefrit is afgelopen.');
  }, seconds * 1000);
}

RegisterNuiCallbackType('action');
on('__cfx_nui:action', async (data, cb) => {
  const action = String(data?.action || '');
  const model = String(data?.model || '');

  if (action === 'close') {
    closeMenu();
    cb({ ok: true });
    return;
  }

  if (action === 'buy') {
    closeMenu();
    emitNet('ht_customdealer:server:purchase', model);
    cb({ ok: true });
    return;
  }

  if (action === 'test') {
    closeMenu();
    await startTestDrive(model);
    cb({ ok: true });
    return;
  }

  cb({ ok: false });
});

onNet('ht_customdealer:client:notify', (message) => notify(message));

onNet('ht_customdealer:client:purchaseResult', (netId, plate, vin) => {
  deleteTestVehicle();
  const vehicle = NetworkGetEntityFromNetworkId(Number(netId));
  if (vehicle && DoesEntityExist(vehicle)) {
    SetVehicleDoorsLocked(vehicle, 1);
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1);
  }
  notify(`Aankoop afgerond: ${plate} | VIN ${vin}`);
});

on('onResourceStop', (stoppedResource) => {
  if (stoppedResource === resourceName) deleteTestVehicle();
});

if (config.blip?.enabled) {
  const blip = AddBlipForCoord(Number(location.x), Number(location.y), Number(location.z));
  SetBlipSprite(blip, Number(config.blip.sprite || 326));
  SetBlipColour(blip, Number(config.blip.color || 3));
  SetBlipScale(blip, Number(config.blip.scale || 0.8));
  SetBlipAsShortRange(blip, true);
  BeginTextCommandSetBlipName('STRING');
  AddTextComponentSubstringPlayerName(String(config.blip.name || 'Autoverkoop'));
  EndTextCommandSetBlipName(blip);
}

setTick(() => {
  const [x, y, z] = GetEntityCoords(PlayerPedId(), false);
  const distance = Math.hypot(x - location.x, y - location.y, z - location.z);
  if (distance > Number(config.markerDistance || 30.0)) return;

  DrawMarker(
    1,
    location.x, location.y, location.z - 1.0,
    0, 0, 0,
    0, 0, 0,
    2.2, 2.2, 0.6,
    80, 155, 255, 120,
    false, false, 2, false, null, null, false
  );

  if (distance <= Number(config.interactDistance || 3.0)) {
    drawText3D(location.x, location.y, location.z + 0.45, '[E] HexTactics Autoverkoop');
    if (IsControlJustReleased(0, 38) && !menuOpen) openMenu();
  }
});
