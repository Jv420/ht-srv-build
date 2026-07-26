local ESX = exports['es_extended']:getSharedObject()
local Config = json.decode(LoadResourceFile(GetCurrentResourceName(), 'config.json') or '{}')
local sessions, profiles, cooldowns = {}, {}, {}

math.randomseed(os.time() + GetGameTimer())

local firstNames = { 'Daan', 'Lars', 'Milan', 'Sophie', 'Emma', 'Julia', 'Sanne', 'Anouk' }
local surnames = { 'De Vries', 'Jansen', 'Visser', 'Smit', 'Bakker', 'Mulder', 'De Boer', 'Dijkstra' }
local streets = { 'Waterstraat', 'Havenweg', 'Farmsumerweg', 'Kustweg', 'Stationsweg', 'Dijklaan' }
local jobs = { 'chauffeur', 'monteur', 'havenarbeider', 'winkelmedewerker', 'kok', 'werkzoekend' }
local contraband = { 'zakje wiet', 'zakje cocaïne', 'inbrekerswerktuig', 'ongeregistreerd mes', 'vuurwapen' }

local function choice(list) return list[math.random(1, #list)] end
local function identifier(xPlayer) return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier end
local function officer(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not xPlayer.job then return nil end
    local minimum = Config.policeJobs and Config.policeJobs[xPlayer.job.name]
    if minimum == nil or tonumber(xPlayer.job.grade or 0) < tonumber(minimum) then return nil end
    if Config.requireDuty then
        local duty = xPlayer.job.onDuty
        if duty == nil then duty = Player(source).state.onduty end
        if duty ~= true then return nil end
    end
    return xPlayer
end
local function limited(source, key)
    local now = GetGameTimer(); cooldowns[source] = cooldowns[source] or {}
    if now < (cooldowns[source][key] or 0) then return true end
    cooldowns[source][key] = now + math.max(500, tonumber(Config.requestCooldownMs) or 1000)
    return false
end
local function entity(netId, expectedType)
    local value = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if value == 0 or not DoesEntityExist(value) or (expectedType and GetEntityType(value) ~= expectedType) then return 0 end
    return value
end
local function closeEnough(source, target, distance)
    local ped = GetPlayerPed(source)
    return ped ~= 0 and target ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(target)) <= distance
end
local function profileName(profile) return ('%s %s'):format(profile.firstName, profile.lastName) end
local function createProfile(netId, vehicleNetId)
    local age = math.random(18, 78)
    local licenseRoll = math.random(100)
    local profile = {
        firstName = choice(firstNames), lastName = choice(surnames), age = age,
        birthDate = ('%02d-%02d-%04d'):format(math.random(1, 28), math.random(1, 12), tonumber(os.date('%Y')) - age),
        address = ('%s %d, Delfzijl'):format(choice(streets), math.random(1, 180)), occupation = choice(jobs),
        idValid = math.random(100) > 7, license = licenseRoll <= 10 and 'none' or (licenseRoll <= 20 and 'expired' or 'valid'),
        alcohol = math.random(100) <= 18 and math.random(20, 180) / 100 or 0.0, drugs = math.random(100) <= 10,
        wanted = math.random(100) <= 8, aggression = math.random(100), inventory = {}, fines = 0,
        arrested = false, escorted = false, vehicleNetId = tonumber(vehicleNetId) or 0, expiresAt = os.time() + 1800
    }
    if math.random(100) <= 25 then profile.inventory[1] = choice(contraband) end
    profiles[tostring(netId)] = profile
    return profile
end
local function getProfile(netId, vehicleNetId)
    local key = tostring(netId); local profile = profiles[key]
    if not profile or profile.expiresAt < os.time() then profile = createProfile(netId, vehicleNetId) end
    if tonumber(vehicleNetId) and tonumber(vehicleNetId) > 0 then profile.vehicleNetId = tonumber(vehicleNetId) end
    return profile
end
local function ticketList()
    local rows = {}
    for code, ticket in pairs(Config.ticketCatalog or {}) do rows[#rows + 1] = { code = code, label = ticket.label, amount = tonumber(ticket.amount) or 0 } end
    table.sort(rows, function(a, b) return a.code < b.code end)
    return rows
end
local function logCase(source, xPlayer, profile, action, details, amount)
    MySQL.insert.await([[INSERT INTO `hextactics_npc_cases` (`officer_identifier`,`officer_name`,`npc_name`,`npc_profile`,`action_type`,`action_details`,`fine_amount`) VALUES (?,?,?,?,?,?,?)]], {
        identifier(xPlayer), xPlayer.getName and xPlayer.getName() or GetPlayerName(source), profileName(profile), json.encode(profile), action, json.encode(details or {}), tonumber(amount) or 0
    })
end
local function validateSession(source, token)
    local session = sessions[source]
    if not session or session.token ~= tostring(token or '') or session.expiresAt < os.time() then return nil end
    local xPlayer = officer(source); if not xPlayer then return nil end
    local npc = entity(session.netId, 1)
    if npc == 0 or not closeEnough(source, npc, tonumber(Config.sessionDistance) or 7.5) then return nil end
    return session, getProfile(session.netId, session.vehicleNetId), xPlayer
end
local function reaction(profile, serious)
    if serious and profile.aggression >= 78 then return 'resist' end
    if profile.aggression >= 90 then return 'flee' end
    return 'comply'
end

RegisterNetEvent('hextactics_npc:requestOpen', function(netId, vehicleNetId)
    local source = source
    if limited(source, 'open') then return end
    local xPlayer = officer(source)
    if not xPlayer then return TriggerClientEvent('hextactics_npc:notify', source, 'Alleen bevoegde agenten kunnen NPC-controles uitvoeren.') end
    local npc = entity(netId, 1)
    if npc == 0 or not closeEnough(source, npc, tonumber(Config.interactionDistance) or 3.2) then return end
    local vehicle = entity(vehicleNetId, 2)
    local safeVehicleNetId = vehicle ~= 0 and closeEnough(source, vehicle, 12.0) and tonumber(vehicleNetId) or 0
    local profile = getProfile(netId, safeVehicleNetId)
    local token = ('%d:%d:%d:%d'):format(source, tonumber(netId), os.time(), math.random(100000, 999999))
    sessions[source] = { token = token, netId = tonumber(netId), vehicleNetId = safeVehicleNetId, expiresAt = os.time() + (tonumber(Config.sessionSeconds) or 180) }
    TriggerClientEvent('hextactics_npc:openMenu', source, { token = token, title = 'NPC politiecontrole', subtitle = 'Identiteit nog niet vastgesteld', arrested = profile.arrested, escorted = profile.escorted, tickets = ticketList() })
end)

RegisterNetEvent('hextactics_npc:performAction', function(token, action, payload)
    local source = source
    if limited(source, 'action') then return end
    action = type(action) == 'string' and action:sub(1, 30) or ''; payload = type(payload) == 'table' and payload or {}
    local session, profile, xPlayer = validateSession(source, token)
    if not session then return TriggerClientEvent('hextactics_npc:actionResult', source, { close = true, message = 'De controlesessie is verlopen.' }) end
    local result = { action = action, arrested = profile.arrested, escorted = profile.escorted }
    if action == 'identity' then
        result.title = 'Identiteitscontrole'; result.subtitle = profileName(profile)
        result.lines = { 'Naam: ' .. profileName(profile), 'Geboortedatum: ' .. profile.birthDate, 'Adres: ' .. profile.address, 'Beroep: ' .. profile.occupation, 'Identiteitsbewijs: ' .. (profile.idValid and 'geldig' or 'ongeldig/ontbreekt') }
        result.behavior = reaction(profile, false)
    elseif action == 'license' then
        result.title = 'Rijbewijscontrole'; result.lines = { 'Status: ' .. profile.license }
    elseif action == 'wanted' then
        result.title = 'Signaleringen'; result.lines = { profile.wanted and 'Actieve signalering gevonden.' or 'Geen actieve signaleringen.' }
    elseif action == 'breathalyzer' then
        result.title = 'Alcohol- en drugstest'; result.lines = { ('Alcohol: %.2f ‰'):format(profile.alcohol), 'Drugstest: ' .. (profile.drugs and 'POSITIEF' or 'negatief') }
    elseif action == 'frisk' then
        result.title = 'Fouillering'; result.lines = { #profile.inventory > 0 and ('Aangetroffen: ' .. table.concat(profile.inventory, ', ')) or 'Geen verboden goederen aangetroffen.' }; result.behavior = reaction(profile, #profile.inventory > 0)
    elseif action == 'vehicle' then
        result.title = 'Voertuigcontrole'
        local vehicle = entity(session.vehicleNetId, 2)
        if vehicle == 0 then result.lines = { 'De NPC bestuurt geen controleerbaar voertuig.' } else
            local plate = GetVehicleNumberPlateText(vehicle); local record
            if GetResourceState('ht_rdw') == 'started' then local ok, value = pcall(function() return exports['ht_rdw']:GetPublicVehicleRecord(plate) end); if ok then record = value end end
            if record then result.lines = { 'Kenteken: ' .. tostring(record.plate), 'VIN: ' .. tostring(record.vin), 'Gestolen: ' .. (record.stolen and 'JA' or 'nee'), 'APK: ' .. (record.apkValid and 'geldig' or 'verlopen'), 'Verzekering: ' .. (record.insuranceValid and 'geldig' or 'ontbreekt/verlopen') }
            else result.lines = { 'Kenteken: ' .. plate, 'NPC-voertuig niet in spelersregister; administratieve status is gesimuleerd.' } end
        end
    elseif action == 'warn' then
        result.title = 'Waarschuwing geregistreerd'; result.lines = { 'De NPC heeft een officiële waarschuwing gekregen.' }; result.behavior = 'comply'
    elseif action == 'ticket' then
        local code = type(payload.code) == 'string' and payload.code:sub(1, 10) or ''; local ticket = Config.ticketCatalog and Config.ticketCatalog[code]
        if not ticket then return end
        local amount = math.max(0, math.floor(tonumber(ticket.amount) or 0)); profile.fines = profile.fines + amount
        result.title = 'Boete uitgeschreven'; result.lines = { 'Feitcode: ' .. code, 'Overtreding: ' .. tostring(ticket.label), ('Bedrag: €%d'):format(amount), ('Totaal dossier: €%d'):format(profile.fines) }; result.behavior = reaction(profile, false)
        logCase(source, xPlayer, profile, action, { code = code, label = ticket.label }, amount)
        return TriggerClientEvent('hextactics_npc:actionResult', source, result)
    elseif action == 'arrest' then
        local grounds = profile.wanted or profile.alcohol >= 0.5 or profile.drugs or #profile.inventory > 0
        if not grounds then result.title = 'Aanhouding geweigerd'; result.lines = { 'Geen server-gevalideerde aanhoudingsgrond gevonden.' }
        else profile.arrested = true; result.arrested = true; result.title = 'NPC aangehouden'; result.lines = { 'Aanhouding geregistreerd in het NPC-dossier.' }; result.behavior = reaction(profile, true) end
    elseif action == 'escort' then
        if not profile.arrested then return end
        profile.escorted = not profile.escorted; result.arrested = true; result.escorted = profile.escorted; result.title = profile.escorted and 'Escort gestart' or 'Escort gestopt'; result.lines = { profile.escorted and 'De NPC volgt de agent.' or 'De NPC blijft staan.' }; result.behavior = profile.escorted and 'escort' or 'handsup'
    elseif action == 'release' then
        profile.arrested = false; profile.escorted = false; result.arrested = false; result.escorted = false; result.title = 'NPC vrijgelaten'; result.lines = { 'De controle is afgerond.' }; result.behavior = 'release'; result.close = true
    else return end
    logCase(source, xPlayer, profile, action, result.lines, 0)
    TriggerClientEvent('hextactics_npc:actionResult', source, result)
end)

RegisterNetEvent('hextactics_npc:closeSession', function(token)
    local source = source; local session = sessions[source]
    if session and session.token == tostring(token or '') then sessions[source] = nil end
end)
AddEventHandler('playerDropped', function() sessions[source] = nil; cooldowns[source] = nil end)
CreateThread(function() while true do Wait(60000); local now = os.time(); for source, session in pairs(sessions) do if session.expiresAt < now then sessions[source] = nil end end; for key, profile in pairs(profiles) do if profile.expiresAt < now then profiles[key] = nil end end end end)
MySQL.ready(function() print('[hextactics_npc_roleplay] Beveiligde NPC-roleplay gestart.') end)
