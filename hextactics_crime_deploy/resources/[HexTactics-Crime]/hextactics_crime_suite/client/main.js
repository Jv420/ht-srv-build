const RESOURCE = GetCurrentResourceName();
const CONFIG = JSON.parse(LoadResourceFile(RESOURCE, 'config.json'));
let state = { reputation: 0, heat: 0, gang: null, jailed: false, police: 0, blackmarket: null, boost: null };
let activeAction = null;
let routeContract = null;
let jail = null;
let menuOpen = false;

const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
const dist = (a, b) => Math.sqrt((a[0]-b.x)**2 + (a[1]-b.y)**2 + (a[2]-b.z)**2);

function notify(message, kind = 'info') {
  SetNotificationTextEntry('STRING');
  AddTextComponentString(`~${kind === 'error' ? 'r' : kind === 'success' ? 'g' : 'b'}~HexTactics~s~: ${message}`);
  DrawNotification(false, false);
}

function help(message) {
  BeginTextCommandDisplayHelp('STRING');
  AddTextComponentSubstringPlayerName(message);
  EndTextCommandDisplayHelp(0, false, true, -1);
}

function openMenu() {
  menuOpen = true;
  SetNuiFocus(true, true);
  SendNuiMessage(JSON.stringify({ action: 'open', state, config: { actions: CONFIG.actions, blackmarket: CONFIG.blackmarket } }));
  emitNet('htcrime:server:requestState');
}

function closeMenu() {
  menuOpen = false;
  SetNuiFocus(false, false);
  SendNuiMessage(JSON.stringify({ action: 'close' }));
}

RegisterCommand('crime', openMenu, false);
RegisterCommand('crimehelp', () => notify('Gebruik /crime, /hotwire, /plateclone, /trackerremove, /boost, /streetsell [item], /ganginvite [id], /crimeevidence en /crimekit (politie).', 'info'), false);
RegisterKeyMapping('crime', 'Open HexTactics Crime-menu', 'keyboard', 'F6');

RegisterNuiCallbackType('close');
on('__cfx_nui:close', (_, cb) => { closeMenu(); cb({ ok: true }); });
RegisterNuiCallbackType('requestState');
on('__cfx_nui:requestState', (_, cb) => { emitNet('htcrime:server:requestState'); cb({ ok: true }); });
RegisterNuiCallbackType('startRoute');
on('__cfx_nui:startRoute', (data, cb) => {
  if (data?.type === 'smuggling') emitNet('htcrime:server:startSmuggling');
  if (data?.type === 'boost') emitNet('htcrime:server:requestBoost');
  closeMenu(); cb({ ok: true });
});
RegisterNuiCallbackType('marketBuy');
on('__cfx_nui:marketBuy', (data, cb) => { emitNet('htcrime:server:marketBuy', String(data.item || ''), Number(data.amount || 1)); cb({ ok: true }); });
RegisterNuiCallbackType('fenceSell');
on('__cfx_nui:fenceSell', (data, cb) => { emitNet('htcrime:server:fenceSell', String(data.item || ''), Number(data.amount || 1)); cb({ ok: true }); });
RegisterNuiCallbackType('convertMarked');
on('__cfx_nui:convertMarked', (data, cb) => { emitNet('htcrime:server:convertMarked', Number(data.amount || 0)); cb({ ok: true }); });
RegisterNuiCallbackType('launder');
on('__cfx_nui:launder', (data, cb) => {
  const nearest = nearestLocation('moneywash', 6.0);
  if (nearest) emitNet('htcrime:server:launder', Number(data.amount || 0), nearest.id);
  else notify('Je staat niet bij een wasserette.', 'error');
  cb({ ok: true });
});
RegisterNuiCallbackType('createGang');
on('__cfx_nui:createGang', (data, cb) => { emitNet('htcrime:server:createGang', String(data.name || ''), String(data.tag || '')); cb({ ok: true }); });
RegisterNuiCallbackType('acceptGang');
on('__cfx_nui:acceptGang', (_, cb) => { emitNet('htcrime:server:acceptGangInvite'); cb({ ok: true }); });

onNet('htcrime:client:notify', notify);
onNet('htcrime:client:state', (payload) => {
  state = payload || state;
  if (menuOpen) SendNuiMessage(JSON.stringify({ action: 'state', state }));
});
onNet('htcrime:client:gangInvite', (invite) => { notify(`Ganguitnodiging van ${invite.name} [${invite.tag}]. Open /crime om te accepteren.`, 'success'); SendNuiMessage(JSON.stringify({ action:'gangInvite', invite })); });
onNet('htcrime:client:setRouteContract', (contract) => {
  routeContract = contract;
  notify(`Contract gestart. Ga naar ${contract.pickup.label}.`, 'success');
  setWaypoint(contract.pickup);
});
onNet('htcrime:client:boostContract', (contract) => {
  state.boost = contract || null;
  if (contract) { notify(`Boostcontract: ${contract.model}.`, 'success'); setWaypoint(contract.delivery); }
});

onNet('htcrime:client:actionStarted', async (payload) => {
  if (activeAction) return;
  activeAction = payload;
  const ped = PlayerPedId();
  TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_WELDING', 0, true);
  FreezeEntityPosition(ped, true);
  const started = GetGameTimer();
  while (activeAction && GetGameTimer() - started < payload.duration * 1000) {
    await wait(0);
    const remaining = Math.max(0, payload.duration - Math.floor((GetGameTimer() - started) / 1000));
    help(`${payload.label}: ~y~${remaining}s~s~ | ~r~BACKSPACE om te annuleren`);
    if (IsControlJustReleased(0, 177)) { activeAction = null; break; }
  }
  ClearPedTasksImmediately(ped);
  FreezeEntityPosition(ped, false);
  if (!activeAction) return notify('Actie geannuleerd.', 'error');
  const finished = activeAction;
  activeAction = null;
  if (finished.actionType.startsWith('vehicle_')) emitNet('htcrime:server:completeVehicleAction', finished.token);
  else if (finished.actionType === 'territory') emitNet('htcrime:server:completeTerritory', finished.token);
  else if (finished.actionType === 'prison_escape') emitNet('htcrime:server:completeEscape', finished.token);
  else emitNet('htcrime:server:completeAction', finished.token);
});
onNet('htcrime:client:actionFinished', () => { activeAction = null; });
onNet('htcrime:client:smugglingStage', (stage) => { if (!routeContract) return; if (stage === 'delivery') { routeContract.stage='delivery'; setWaypoint(routeContract.delivery); notify(`Breng de kist naar ${routeContract.delivery.label}.`, 'success'); } else if (stage === 'complete') { routeContract=null; notify('Smokkelroute afgerond.', 'success'); } });
onNet('htcrime:client:vehicleResult', (netId, result) => {
  const vehicle = NetworkGetEntityFromNetworkId(Number(netId));
  if (!vehicle || !DoesEntityExist(vehicle)) return;
  if (result.unlocked) { SetVehicleDoorsLocked(vehicle, 1); SetVehicleEngineOn(vehicle, true, true, false); }
  if (result.newPlate) SetVehicleNumberPlateText(vehicle, String(result.newPlate));
});

onNet('htcrime:client:dispatch', (payload) => {
  notify(`${payload.code}: ${payload.message}`, 'error');
  const radius = AddBlipForRadius(payload.x, payload.y, payload.z, payload.radius || 70.0);
  SetBlipColour(radius, 1); SetBlipAlpha(radius, 90);
  const blip = AddBlipForCoord(payload.x, payload.y, payload.z);
  SetBlipSprite(blip, 161); SetBlipColour(blip, 1); SetBlipScale(blip, 1.0);
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString(`${payload.code} ${payload.message}`); EndTextCommandSetBlipName(blip);
  setTimeout(() => { RemoveBlip(radius); RemoveBlip(blip); }, (payload.duration || 90) * 1000);
});

onNet('htcrime:client:evidenceList', (rows) => {
  if (!rows?.length) return notify('Geen onbeveiligd bewijs in de buurt.', 'info');
  rows.forEach(row => {
    const blip = AddBlipForCoord(Number(row.x), Number(row.y), Number(row.z));
    SetBlipSprite(blip, 162); SetBlipColour(blip, 5); SetBlipScale(blip, 0.65);
    setTimeout(() => RemoveBlip(blip), 60000);
    emit('chat:addMessage', { color: [255, 210, 70], args: ['HexTactics Bewijs', `#${row.id} · ${row.evidence_type} · ${row.fingerprint || 'geen afdruk'} · /collectevidence ${row.id}`] });
  });
  notify(`${rows.length} bewijsstukken gemarkeerd en in chat vermeld.`, 'success');
});

onNet('htcrime:client:jail', (payload) => {
  jail = { remaining: Number(payload.remaining || 0), reason: payload.reason || '', prison: payload.prison || CONFIG.prison };
  const p = jail.prison.spawn;
  SetEntityCoords(PlayerPedId(), p.x, p.y, p.z, false, false, false, false); SetEntityHeading(PlayerPedId(), p.heading || 0);
  notify(`Gevangenisstraf: ${Math.ceil(jail.remaining/60)} minuten.`, 'error');
});
onNet('htcrime:client:release', (location) => {
  jail = null; const p = location || CONFIG.prison.release;
  SetEntityCoords(PlayerPedId(), p.x, p.y, p.z, false, false, false, false); SetEntityHeading(PlayerPedId(), p.heading || 0);
  notify('Je bent vrijgelaten.', 'success');
});
onNet('htcrime:client:jailTimeReduced', (seconds) => { if (jail) jail.remaining = Math.max(0, jail.remaining - Number(seconds || 0)); });

function nearestLocation(type, maximum = 3.0) {
  const list = CONFIG.locations[type] || [];
  const coords = GetEntityCoords(PlayerPedId());
  let nearest = null, best = maximum;
  for (const location of list) { const d = dist(coords, location); if (d < best) { best = d; nearest = location; } }
  return nearest;
}

function closestVehicle(maximum = 6.0) {
  const coords = GetEntityCoords(PlayerPedId()); let closest = 0, best = maximum;
  for (const vehicle of GetGamePool('CVehicle')) {
    const vcoords = GetEntityCoords(vehicle); const d = Math.sqrt((coords[0]-vcoords[0])**2+(coords[1]-vcoords[1])**2+(coords[2]-vcoords[2])**2);
    if (d < best) { best = d; closest = vehicle; }
  }
  return closest;
}

function closestCivilianPed(maximum = 4.0) {
  const me = PlayerPedId(), coords = GetEntityCoords(me); let closest = 0, best = maximum;
  for (const ped of GetGamePool('CPed')) {
    if (ped === me || IsPedAPlayer(ped) || IsEntityDead(ped) || !IsPedHuman(ped)) continue;
    const pcoords = GetEntityCoords(ped); const d = Math.sqrt((coords[0]-pcoords[0])**2+(coords[1]-pcoords[1])**2+(coords[2]-pcoords[2])**2);
    if (d < best) { best = d; closest = ped; }
  }
  return closest;
}

function startVehicleAction(action) {
  const vehicle = closestVehicle();
  if (!vehicle) return notify('Geen voertuig dichtbij.', 'error');
  emitNet('htcrime:server:startVehicleAction', action, NetworkGetNetworkIdFromEntity(vehicle));
}
RegisterCommand('hotwire', () => startVehicleAction('hotwire'), false);
RegisterCommand('plateclone', () => startVehicleAction('plateclone'), false);
RegisterCommand('trackerremove', () => startVehicleAction('trackerremove'), false);
RegisterCommand('stealecu', () => startVehicleAction('ecu'), false);
RegisterCommand('boost', () => emitNet('htcrime:server:requestBoost'), false);
RegisterCommand('streetsell', (_, args) => {
  const ped = closestCivilianPed(4.0);
  if (!ped) return notify('Geen geschikte NPC-koper dichtbij.', 'error');
  emitNet('htcrime:server:streetSell', String(args[0] || 'weed_bag'));
}, false);
RegisterCommand('ganginvite', (_, args) => emitNet('htcrime:server:inviteGang', Number(args[0] || 0)), false);
RegisterCommand('gangleave', () => emitNet('htcrime:server:leaveGang'), false);
RegisterCommand('crimeevidence', () => emitNet('htcrime:server:requestEvidence'), false);
RegisterCommand('collectevidence', (_, args) => emitNet('htcrime:server:collectEvidence', Number(args[0] || 0)), false);
RegisterCommand('crimecraft', (_, args) => emitNet('htcrime:server:craft', String(args[0] || '')), false);

function setWaypoint(location) { if (location) SetNewWaypoint(location.x, location.y); }

setInterval(() => {
  emitNet('htcrime:server:requestState');
  if (jail) jail.remaining = Math.max(0, jail.remaining - 10);
}, 10000);

on('onClientResourceStart', (name) => { if (name === RESOURCE) { emitNet('htcrime:server:requestState'); emitNet('htcrime:server:requestJailState'); } });

setTick(() => {
  const ped = PlayerPedId(); const coords = GetEntityCoords(ped);

  for (const [type, locations] of Object.entries(CONFIG.locations)) {
    if (!['store_register','store_safe','atm','warehouse','weed_harvest','weed_process','coke_process','meth_process','territory'].includes(type)) continue;
    for (const location of locations) {
      const d = dist(coords, location);
      if (d < 20.0) DrawMarker(1, location.x, location.y, location.z-1.0, 0,0,0,0,0,0,1.0,1.0,0.35, 255,80,40,120, false,false,2,false,null,null,false);
      if (d < 2.2 && !activeAction) {
        help(`Druk ~INPUT_CONTEXT~ voor ~y~${CONFIG.actions[type]?.label || location.label}`);
        if (IsControlJustReleased(0, 38)) {
          if (type === 'territory') emitNet('htcrime:server:startTerritory', location.id);
          else emitNet('htcrime:server:startAction', type, location.id);
        }
      }
    }
  }

  if (state.blackmarket) {
    const d = dist(coords, state.blackmarket);
    if (d < 20.0) DrawMarker(1, state.blackmarket.x, state.blackmarket.y, state.blackmarket.z-1.0, 0,0,0,0,0,0,1.2,1.2,0.4, 120,40,180,120, false,false,2,false,null,null,false);
    if (d < 2.5) { help('Druk ~INPUT_CONTEXT~ voor de ~p~zwarte markt'); if (IsControlJustReleased(0,38)) openMenu(); }
  }

  if (routeContract) {
    const target = routeContract.stage === 'delivery' ? routeContract.delivery : routeContract.pickup;
    const d = dist(coords, target);
    if (d < 20.0) DrawMarker(1,target.x,target.y,target.z-1.0,0,0,0,0,0,0,1.4,1.4,0.5,40,180,255,130,false,false,2,false,null,null,false);
    if (d < 2.5 && !activeAction) {
      help(`Druk ~INPUT_CONTEXT~ voor ${target.label}`);
      if (IsControlJustReleased(0,38)) {
        const actionType = routeContract.stage === 'delivery' ? 'smuggling_delivery' : 'smuggling_pickup';
        emitNet('htcrime:server:startAction', actionType, target.id);
      }
    }
  }

  if (state.boost?.delivery) {
    const d = dist(coords, state.boost.delivery);
    if (d < 25.0) DrawMarker(36,state.boost.delivery.x,state.boost.delivery.y,state.boost.delivery.z+0.5,0,0,0,0,0,0,1.5,1.5,1.5,255,170,20,150,false,false,2,true,null,null,false);
    if (d < 5.0) { help('Druk ~INPUT_CONTEXT~ om het boostvoertuig af te leveren'); if (IsControlJustReleased(0,38)) { const v=GetVehiclePedIsIn(ped,false); if(v) emitNet('htcrime:server:deliverBoost',NetworkGetNetworkIdFromEntity(v)); } }
  }

  if (jail) {
    const p = jail.prison; const d = dist(coords, p.center);
    if (d > p.radius) { SetEntityCoords(ped,p.spawn.x,p.spawn.y,p.spawn.z,false,false,false,false); notify('Je mag de gevangenis niet verlaten.', 'error'); }
    const workD = dist(coords,p.work); if(workD<2.5){help('Druk ~INPUT_CONTEXT~ voor gevangeniswerk'); if(IsControlJustReleased(0,38)) emitNet('htcrime:server:prisonWork');}
    const escD = dist(coords,p.escape); if(escD<2.5){help('Druk ~INPUT_CONTEXT~ voor een ontsnappingspoging'); if(IsControlJustReleased(0,38)) emitNet('htcrime:server:startEscape');}
  }
});
