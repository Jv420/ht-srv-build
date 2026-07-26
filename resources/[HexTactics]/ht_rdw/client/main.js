'use strict';

const resourceName = GetCurrentResourceName();
const config = JSON.parse(LoadResourceFile(resourceName, 'config.json'));
const location = config.location;
let menuOpen = false;
let activeVehicle = 0;
let busy = false;
let pendingTransfer = null;

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

function getClosestVehicle(maxDistance = Number(config.vehicleDistance || 8.0)) {
  const [px, py, pz] = GetEntityCoords(PlayerPedId(), false);
  let closest = 0;
  let closestDistance = maxDistance + 0.001;
  for (const vehicle of GetGamePool('CVehicle')) {
    if (!DoesEntityExist(vehicle)) continue;
    const [x, y, z] = GetEntityCoords(vehicle, false);
    const distance = Math.hypot(px - x, py - y, pz - z);
    if (distance < closestDistance) {
      closest = vehicle;
      closestDistance = distance;
    }
  }
  return closest;
}

function openMenu(vehicle) {
  activeVehicle = vehicle || 0;
  menuOpen = true;
  SetNuiFocus(true, true);
  SendNuiMessage(JSON.stringify({ type: 'open', hasVehicle: Boolean(activeVehicle) }));
  emitNet('ht_rdw:server:requestMenu', activeVehicle ? NetworkGetNetworkIdFromEntity(activeVehicle) : 0);
}

function closeMenu() {
  menuOpen = false;
  SetNuiFocus(false, false);
  SendNuiMessage(JSON.stringify({ type: 'close' }));
}

async function progress(label, duration) {
  if (busy) return false;
  busy = true;
  const endAt = GetGameTimer() + duration;
  FreezeEntityPosition(PlayerPedId(), true);
  while (GetGameTimer() < endAt) {
    await new Promise((resolve) => setTimeout(resolve, 0));
    DisableAllControlActions(0);
    EnableControlAction(0, 200, true);
    drawText3D(location.x, location.y, location.z + 1.1, `${label} (${Math.ceil((endAt - GetGameTimer()) / 1000)}s)`);
    if (IsControlJustReleased(0, 200)) {
      FreezeEntityPosition(PlayerPedId(), false);
      busy = false;
      notify('Keuring geannuleerd.');
      return false;
    }
  }
  FreezeEntityPosition(PlayerPedId(), false);
  busy = false;
  return true;
}

function currentNetId() {
  return activeVehicle && DoesEntityExist(activeVehicle) ? NetworkGetNetworkIdFromEntity(activeVehicle) : 0;
}

RegisterNuiCallbackType('action');
on('__cfx_nui:action', async (data, cb) => {
  const action = String(data?.action || '');

  if (action === 'close') {
    closeMenu();
    cb({ ok: true });
    return;
  }

  if (action === 'inspect') {
    emitNet('ht_rdw:server:inspect', currentNetId());
    cb({ ok: true });
    return;
  }

  if (action === 'insurance') {
    emitNet('ht_rdw:server:insurance', currentNetId());
    cb({ ok: true });
    return;
  }

  if (action === 'apk') {
    closeMenu();
    const completed = await progress('APK-keuring uitvoeren', Number(config.apkDurationMs || 10000));
    if (completed) emitNet('ht_rdw:server:apk', currentNetId());
    cb({ ok: completed });
    return;
  }

  if (action === 'register') {
    const targetId = Number(data.targetId);
    if (!Number.isInteger(targetId) || targetId < 1) {
      notify('Vul een geldig server-ID in.');
      cb({ ok: false });
      return;
    }
    emitNet('ht_rdw:server:registerTarget', currentNetId(), targetId);
    cb({ ok: true });
    return;
  }

  if (action === 'payFine') {
    emitNet('ht_rdw:server:payFine', Number(data.fineId));
    cb({ ok: true });
    return;
  }

  cb({ ok: false });
});


function respondToTransfer(accepted) {
  if (!pendingTransfer) return;
  const token = pendingTransfer.token;
  pendingTransfer = null;
  emitNet('ht_rdw:server:respondTransfer', token, accepted === true);
}

RegisterCommand('+htAcceptTransfer', () => respondToTransfer(true), false);
RegisterCommand('-htAcceptTransfer', () => {}, false);
RegisterKeyMapping('+htAcceptTransfer', 'RDW-tenaamstelling accepteren', 'keyboard', 'Y');

RegisterCommand('+htDeclineTransfer', () => respondToTransfer(false), false);
RegisterCommand('-htDeclineTransfer', () => {}, false);
RegisterKeyMapping('+htDeclineTransfer', 'RDW-tenaamstelling weigeren', 'keyboard', 'N');

onNet('ht_rdw:client:confirmTransfer', (data) => {
  if (!data || typeof data.token !== 'string') return;
  pendingTransfer = {
    token: data.token,
    plate: String(data.plate || 'onbekend'),
    price: Math.max(0, Number(data.price || 0)),
    staffName: String(data.staffName || 'RDW-medewerker'),
    expiresAt: GetGameTimer() + Math.max(5, Number(data.expiresIn || 30)) * 1000
  };
  notify(`Tenaamstelling ${pendingTransfer.plate}: druk Y voor akkoord of N om te weigeren.`);
});

onNet('ht_rdw:client:notify', (message) => notify(message));
onNet('ht_rdw:client:menuData', (data) => {
  SendNuiMessage(JSON.stringify({ type: 'data', data: data || {} }));
});

setTick(() => {
  if (pendingTransfer) {
    if (GetGameTimer() > pendingTransfer.expiresAt) {
      pendingTransfer = null;
      notify('De tenaamstellingsaanvraag is verlopen.');
    } else {
      BeginTextCommandDisplayHelp('STRING');
      AddTextComponentSubstringPlayerName(
        `~b~RDW ${pendingTransfer.plate}~s~ voor €${pendingTransfer.price}: ~g~Y accepteren~s~ / ~r~N weigeren~s~`
      );
      EndTextCommandDisplayHelp(0, false, true, -1);
    }
  }

  const [x, y, z] = GetEntityCoords(PlayerPedId(), false);
  const distance = Math.hypot(x - location.x, y - location.y, z - location.z);
  if (distance > Number(config.markerDistance || 25.0)) return;

  DrawMarker(
    1,
    location.x, location.y, location.z - 1.0,
    0, 0, 0,
    0, 0, 0,
    3.2, 3.2, 0.7,
    70, 130, 255, 120,
    false, false, 2, false, null, null, false
  );

  if (distance <= Number(config.interactDistance || 3.0)) {
    drawText3D(location.x, location.y, location.z + 0.55, '[E] RDW / APK');
    if (IsControlJustReleased(0, 38) && !menuOpen && !busy) {
      openMenu(getClosestVehicle());
    }
  }
});

setInterval(() => {
  const ped = PlayerPedId();
  const vehicle = GetVehiclePedIsIn(ped, false);
  if (!vehicle || GetPedInVehicleSeat(vehicle, -1) !== ped) return;
  emitNet('ht_rdw:server:roadCheck', NetworkGetNetworkIdFromEntity(vehicle));
}, Math.max(30000, Number(config.fines?.checkIntervalMs || 60000)));
