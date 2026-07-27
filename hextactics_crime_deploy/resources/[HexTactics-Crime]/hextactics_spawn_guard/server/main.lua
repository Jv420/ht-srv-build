local ESX = exports['es_extended']:getSharedObject()

local REPORT_EVENT <const> = 'ht_spawn_guard:server:report'
local RETRY_EVENT <const> = 'ht_spawn_guard:client:retrySetup'
local REPORT_COOLDOWN_MS <const> = 5000
local RETRY_COOLDOWN_MS <const> = 60000

local allowedStages <const> = {
    network_active = true,
    retry_request = true,
    retry_started = true,
    player_loaded = true,
    player_spawned = true,
    identity_opened = true,
    timeout = true,
}

local lastReport = {}
local lastRetry = {}

local function sanitizeText(value, maximumLength)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('[\r\n\t]', ' ')
    return value:sub(1, maximumLength or 120)
end

local function getResourceStates()
    local names <const> = {
        'es_extended',
        'esx_identity',
        'skinchanger',
        'esx_skin',
        'esx_multicharacter',
        'spawnmanager',
        'mapmanager',
        'basic-gamemode',
        'fivem-map-skater',
    }

    local states = {}
    for index = 1, #names do
        local name <const> = names[index]
        states[name] = GetResourceState(name)
    end

    return states
end

local function canReport(source)
    local now <const> = GetGameTimer()
    local nextAllowed <const> = lastReport[source] or 0

    if now < nextAllowed then
        return false
    end

    lastReport[source] = now + REPORT_COOLDOWN_MS
    return true
end

local function canRetry(source)
    local now <const> = GetGameTimer()
    local nextAllowed <const> = lastRetry[source] or 0

    if now < nextAllowed then
        return false
    end

    lastRetry[source] = now + RETRY_COOLDOWN_MS
    return true
end

RegisterNetEvent(REPORT_EVENT, function(stage, details)
    local source <const> = source

    if source <= 0 or not canReport(source) then
        return
    end

    stage = sanitizeText(stage, 32)
    if not allowedStages[stage] then
        print(('[hextactics_spawn_guard] Ongeldige rapportfase van source %d.'):format(source))
        return
    end

    details = type(details) == 'table' and details or {}
    local player = ESX.GetPlayerFromId(source)
    local playerName = player and player.getName and player.getName() or GetPlayerName(source) or 'Onbekend'
    local identifier = player and player.getIdentifier and player.getIdentifier() or 'nog-geen-xPlayer'
    local note = sanitizeText(details.note, 160)

    print(('[hextactics_spawn_guard] source=%d speler=%s identifier=%s fase=%s note=%s'):format(
        source,
        sanitizeText(playerName, 64),
        sanitizeText(identifier, 80),
        stage,
        note
    ))

    if stage ~= 'retry_request' then
        return
    end

    if not canRetry(source) then
        return
    end

    local states <const> = getResourceStates()
    if states.es_extended ~= 'started' or states.esx_multicharacter ~= 'started' then
        print(('[hextactics_spawn_guard] Herstel geweigerd voor source %d: ESX/multicharacter niet gestart.'):format(source))
        return
    end

    if states.mapmanager == 'started' or states['basic-gamemode'] == 'started' or states['fivem-map-skater'] == 'started' then
        print(('[hextactics_spawn_guard] Herstel geweigerd voor source %d: conflicterende gamemode-resource actief.'):format(source))
        TriggerClientEvent('ht_spawn_guard:client:conflict', source, states)
        return
    end

    TriggerClientEvent(RETRY_EVENT, source)
end)

AddEventHandler('playerDropped', function()
    local source <const> = source
    lastReport[source] = nil
    lastRetry[source] = nil
end)

RegisterCommand('spawncheck', function(source)
    if source > 0 and not IsPlayerAceAllowed(source, 'hextactics.admin') then
        return
    end

    local states <const> = getResourceStates()
    print('^5========== HexTactics spawncontrole ==========^7')
    for name, state in pairs(states) do
        print(('%-28s %s'):format(name, state))
    end
end, false)
