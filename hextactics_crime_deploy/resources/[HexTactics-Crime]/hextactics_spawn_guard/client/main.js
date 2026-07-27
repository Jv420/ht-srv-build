const RESOURCE = GetCurrentResourceName();
const REPORT_EVENT = 'ht_spawn_guard:server:report';

const state = {
  networkActive: false,
  playerLoaded: false,
  playerSpawned: false,
  identityOpened: false,
  retrySent: false,
};

const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function report(stage, note = '') {
  emitNet(REPORT_EVENT, stage, {
    note: String(note).slice(0, 160),
  });
}

function resourceSnapshot() {
  const resources = [
    'es_extended',
    'esx_identity',
    'skinchanger',
    'esx_skin',
    'esx_multicharacter',
    'spawnmanager',
    'mapmanager',
    'basic-gamemode',
    'fivem-map-skater',
  ];

  return resources.map((name) => `${name}=${GetResourceState(name)}`).join(', ');
}

onNet('esx:playerLoaded', () => {
  state.playerLoaded = true;
  report('player_loaded', resourceSnapshot());
});

on('esx:onPlayerSpawn', () => {
  state.playerSpawned = true;
  report('player_spawned', resourceSnapshot());
});

on('esx_identity:showRegisterIdentity', () => {
  state.identityOpened = true;
  report('identity_opened', resourceSnapshot());
});

onNet('ht_spawn_guard:client:conflict', (states) => {
  console.error(`[${RESOURCE}] Spawn geblokkeerd door conflicterende resources: ${JSON.stringify(states)}`);
});

onNet('ht_spawn_guard:client:retrySetup', async () => {
  if (state.playerLoaded || state.playerSpawned) {
    return;
  }

  if (GetResourceState('esx_multicharacter') !== 'started') {
    console.error(`[${RESOURCE}] Herstel afgebroken: esx_multicharacter is niet gestart.`);
    return;
  }

  ShutdownLoadingScreen();
  ShutdownLoadingScreenNui();
  DoScreenFadeOut(0);
  await wait(250);

  report('retry_started', resourceSnapshot());
  emitNet('esx_multicharacter:SetupCharacters');
});

async function monitorJoinFlow() {
  while (!NetworkIsPlayerActive(PlayerId())) {
    await wait(250);
  }

  state.networkActive = true;
  report('network_active', resourceSnapshot());

  await wait(15000);

  if (!state.playerLoaded && !state.playerSpawned && !state.retrySent) {
    state.retrySent = true;
    console.warn(`[${RESOURCE}] ESX playerLoaded bleef uit; veilige multicharacter-herstelpoging aangevraagd.`);
    report('retry_request', resourceSnapshot());
  }

  await wait(20000);

  if (!state.playerSpawned) {
    const phase = state.playerLoaded
      ? 'playerLoaded ontvangen maar esx:onPlayerSpawn bleef uit'
      : state.identityOpened
        ? 'identity geopend maar speler niet gespawned'
        : 'multicharacter/identity leverde geen spawn op';

    console.error(`[${RESOURCE}] Joinflow timeout: ${phase}. ${resourceSnapshot()}`);
    report('timeout', `${phase}; ${resourceSnapshot()}`);
  }
}

on('onClientResourceStart', (resourceName) => {
  if (resourceName !== RESOURCE) {
    return;
  }

  monitorJoinFlow().catch((error) => {
    console.error(`[${RESOURCE}] Onverwachte clientfout: ${error?.stack || error}`);
  });
});
