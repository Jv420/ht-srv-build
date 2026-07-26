'use strict';

const resourceName = GetCurrentResourceName();
let config = {};
let menuOpen = false;
let currentSession = null;
let currentPed = 0;
let interactionLockedUntil = 0;

try {
  config = JSON.parse(LoadResourceFile(resourceName, 'config.json') || '{}');
} catch (error) {
  console.error('[hextactics_npc_roleplay] config.json fout:', error);
}

function notify(message) {
  BeginTextCommandThefeedPost('STRING');
  AddTextComponentSubstringPlayerName(String(message));
  EndTextCommandThefeedPostTicker(false, false);
}

function distanceBetween(first, second) {
  const [ax, ay, az] = GetEntityCoords(first, false);
  const [bx, by, bz] = GetEntityCoords(second, false);
  return Math.hypot(ax - bx, ay - by, az - bz);
}

function closestNpc(maxDistance) {
  const playerPed = PlayerPedId();
  let closest = 0;
  let closestDistance = Number(maxDistance || 3.2);

  for (const ped of GetGamePool('CPed')) {
    if (!DoesEntityExist(ped) || ped === playerPed || IsPedAPlayer(ped)) continue;
    if (!IsPedHuman(ped) || IsEntityDead(ped)) continue;
    const distance = distanceBetween(playerPed, ped);
    if (distance < closestDistance) {
      closest = ped;
      closestDistance = distance;
    }
  }

  return closest;
}

function networkEntity(entity) {
  if (!entity || entity === 0) return 0;
  if (!NetworkGetEntityIsNetworked(entity)) NetworkRegisterEntityAsNetworked(entity);
  return NetworkGetNetworkIdFromEntity(entity);
}

function vehicleDrivenByPed(ped) {
  const vehicle = GetVehiclePedIsIn(ped, false);
  if (!vehicle || vehicle === 0) return 0;
  if (GetPedInVehicleSeat(vehicle, -1) !== ped && GetPedInVehicleSeat(vehicle, 0) !== ped) return 0;
  return vehicle;
}

function openNpcInteraction() {
  const now = GetGameTimer();
  if (menuOpen || now < interactionLockedUntil) return;
  interactionLockedUntil = now + 1000;

  const ped = closestNpc(config.interactionDistance || 3.2);
  if (!ped) {
    notify('Geen levende NPC dichtbij genoeg.');
    return;
  }

  const pedNetId = networkEntity(ped);
  if (!pedNetId) {
    notify('Deze NPC kon niet veilig worden gekoppeld aan de server.');
    return;
  }

  const vehicle = vehicleDrivenByPed(ped);
  const vehicleNetId = networkEntity(vehicle);
  currentPed = ped;
  emitNet('hextactics_npc:requestOpen', pedNetId, vehicleNetId);
}

function closeMenu(sendServer = true) {
  if (sendServer && currentSession?.token) {
    emitNet('hextactics_npc:closeSession', currentSession.token);
  }
  menuOpen = false;
  SetNuiFocus(false, false);
  SendNuiMessage(JSON.stringify({ type: 'close' }));
  currentSession = null;
}

function applyBehavior(behavior) {
  const ped = currentPed;
  if (!behavior || !ped || !DoesEntityExist(ped)) return;
  const playerPed = PlayerPedId();

  SetEntityAsMissionEntity(ped, true, true);
  SetBlockingOfNonTemporaryEvents(ped, true);

  switch (behavior) {
    case 'flee':
      closeMenu(false);
      ClearPedTasksImmediately(ped);
      TaskSmartFleePed(ped, playerPed, 180.0, -1, false, false);
      break;
    case 'resist':
      closeMenu(false);
      ClearPedTasksImmediately(ped);
      TaskCombatPed(ped, playerPed, 0, 16);
      break;
    case 'handsup':
      ClearPedTasksImmediately(ped);
      TaskHandsUp(ped, -1, playerPed, -1, true);
      break;
    case 'escort':
      ClearPedTasks(ped);
      TaskGoToEntity(ped, playerPed, -1, 1.2, 2.0, 1073741824, 0);
      break;
    case 'comply':
      TaskTurnPedToFaceEntity(ped, playerPed, 1500);
      break;
    case 'argue':
      TaskTurnPedToFaceEntity(ped, playerPed, 1500);
      PlayAmbientSpeech1(ped, 'GENERIC_FUCK_YOU', 'SPEECH_PARAMS_FORCE');
      break;
    case 'release':
      ClearPedTasksImmediately(ped);
      SetBlockingOfNonTemporaryEvents(ped, false);
      TaskWanderStandard(ped, 10.0, 10);
      break;
    default:
      break;
  }
}

setTick(() => {
  if (menuOpen || IsPauseMenuActive()) return;
  const altPressed = IsControlPressed(0, 19);
  const eReleased = IsControlJustReleased(0, 38);
  if (altPressed && eReleased) openNpcInteraction();
});

RegisterCommand('npccontrole', openNpcInteraction, false);

onNet('hextactics_npc:openMenu', (data) => {
  if (!data?.token || !currentPed || !DoesEntityExist(currentPed)) return;
  currentSession = data;
  menuOpen = true;
  SetNuiFocus(true, true);
  SendNuiMessage(JSON.stringify({ type: 'open', data }));
  TaskTurnPedToFaceEntity(currentPed, PlayerPedId(), 1500);
});

onNet('hextactics_npc:actionResult', (result) => {
  if (!result) return;
  applyBehavior(result.behavior);
  if (result.subtitle && currentSession) currentSession.subtitle = result.subtitle;
  if (currentSession) {
    currentSession.arrested = Boolean(result.arrested);
    currentSession.escorted = Boolean(result.escorted);
  }
  SendNuiMessage(JSON.stringify({ type: 'result', data: result }));
  if (result.message) notify(result.message);
  if (result.close) setTimeout(() => closeMenu(false), 900);
});

onNet('hextactics_npc:notify', notify);

RegisterNuiCallbackType('action');
on('__cfx_nui:action', (data, callback) => {
  if (!currentSession?.token || typeof data?.action !== 'string') {
    callback({ ok: false });
    return;
  }
  emitNet('hextactics_npc:performAction', currentSession.token, data.action, data.payload || {});
  callback({ ok: true });
});

RegisterNuiCallbackType('close');
on('__cfx_nui:close', (_data, callback) => {
  closeMenu(true);
  callback({ ok: true });
});

on('onClientResourceStop', (stoppedResource) => {
  if (stoppedResource === resourceName) {
    SetNuiFocus(false, false);
  }
});
