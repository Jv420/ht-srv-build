local ESX = exports['es_extended']:getSharedObject()
local resourceName = GetCurrentResourceName()
local rawConfig = LoadResourceFile(resourceName, 'config.json')
assert(rawConfig, ('[%s] config.json ontbreekt'):format(resourceName))
Config = json.decode(rawConfig)
assert(type(Config) == 'table', ('[%s] config.json is ongeldig'):format(resourceName))

HTCrime = HTCrime or {}
HTCrime.Config = Config
HTCrime.Sessions = {}
HTCrime.RateLimits = {}
HTCrime.BoostContracts = {}
HTCrime.PendingInvites = {}

math.randomseed(os.time() + GetGameTimer())

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function HTCrime.NormalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    if #plate < 1 or #plate > 12 or not plate:match('^[A-Z0-9%-]+$') then return nil end
    return plate
end

function HTCrime.GetPlayer(source)
    source = tonumber(source)
    if not source then return nil end
    return ESX.GetPlayerFromId(source)
end

function HTCrime.Identifier(xPlayer)
    if not xPlayer then return nil end
    return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
end

function HTCrime.PlayerName(xPlayer)
    if not xPlayer then return 'Onbekend' end
    return xPlayer.getName and xPlayer.getName() or xPlayer.name or 'Onbekend'
end

function HTCrime.Notify(source, message, kind)
    TriggerClientEvent('htcrime:client:notify', source, tostring(message), kind or 'info')
end

function HTCrime.Limited(source, action, overrideMs)
    local now = GetGameTimer()
    local key = tostring(action or 'default')
    HTCrime.RateLimits[source] = HTCrime.RateLimits[source] or {}
    local nextAllowed = HTCrime.RateLimits[source][key] or 0
    if now < nextAllowed then return true end
    HTCrime.RateLimits[source][key] = now + math.max(250, tonumber(overrideMs) or tonumber(Config.rateLimitMs) or 900)
    return false
end

function HTCrime.IsPolice(xPlayer)
    if not xPlayer or not xPlayer.job then return false end
    for _, jobName in ipairs(Config.policeJobs or {}) do
        if xPlayer.job.name == jobName then return true end
    end
    return false
end

function HTCrime.PoliceCount()
    local count = 0
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if HTCrime.IsPolice(xPlayer) then count = count + 1 end
    end
    return count
end

function HTCrime.PlayerCoords(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

function HTCrime.Near(source, target, maxDistance)
    if type(target) ~= 'table' then return false end
    local coords = HTCrime.PlayerCoords(source)
    if not coords then return false end
    local tx, ty, tz = tonumber(target.x), tonumber(target.y), tonumber(target.z)
    if not tx or not ty or not tz then return false end
    return #(coords - vector3(tx, ty, tz)) <= (tonumber(maxDistance) or tonumber(Config.maxInteractionDistance) or 6.0)
end

function HTCrime.Location(actionType, locationId)
    local list = Config.locations and Config.locations[actionType]
    if type(list) ~= 'table' or type(locationId) ~= 'string' then return nil end
    for _, location in ipairs(list) do
        if location.id == locationId then return location end
    end
    return nil
end

function HTCrime.InventoryCount(source, item)
    if type(item) ~= 'string' then return 0 end
    return tonumber(exports.ox_inventory:Search(source, 'count', item)) or 0
end

function HTCrime.HasItems(source, required)
    if type(required) ~= 'table' then return true end
    for item, amount in pairs(required) do
        if HTCrime.InventoryCount(source, item) < math.max(1, math.floor(tonumber(amount) or 1)) then
            return false, item
        end
    end
    return true
end

function HTCrime.RemoveItems(source, required)
    if type(required) ~= 'table' then return true end
    local removed = {}
    for item, amount in pairs(required) do
        amount = math.max(1, math.floor(tonumber(amount) or 1))
        if not exports.ox_inventory:RemoveItem(source, item, amount) then
            for rollbackItem, rollbackAmount in pairs(removed) do
                exports.ox_inventory:AddItem(source, rollbackItem, rollbackAmount)
            end
            return false
        end
        removed[item] = amount
    end
    return true
end

function HTCrime.AddItem(source, item, amount, metadata)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    return exports.ox_inventory:AddItem(source, item, amount, metadata)
end

function HTCrime.RemoveItem(source, item, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    return exports.ox_inventory:RemoveItem(source, item, amount)
end

function HTCrime.Profile(identifier)
    local row = MySQL.single.await('SELECT `identifier`,`reputation`,`heat`,`gang_id` FROM `ht_crime_profiles` WHERE `identifier`=? LIMIT 1', { identifier })
    if row then return row end
    MySQL.insert.await('INSERT IGNORE INTO `ht_crime_profiles` (`identifier`) VALUES (?)', { identifier })
    return { identifier = identifier, reputation = 0, heat = 0, gang_id = nil }
end

function HTCrime.ChangeProfile(identifier, reputationDelta, heatDelta)
    if type(identifier) ~= 'string' then return end
    reputationDelta = math.floor(tonumber(reputationDelta) or 0)
    heatDelta = math.floor(tonumber(heatDelta) or 0)
    MySQL.insert.await('INSERT IGNORE INTO `ht_crime_profiles` (`identifier`) VALUES (?)', { identifier })
    MySQL.update.await('UPDATE `ht_crime_profiles` SET `reputation`=GREATEST(0,`reputation`+?),`heat`=LEAST(?,GREATEST(0,`heat`+?)),`last_seen`=NOW() WHERE `identifier`=?', {
        reputationDelta, tonumber(Config.maxHeat) or 100, heatDelta, identifier
    })
end

function HTCrime.AddCash(xPlayer, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 or not xPlayer then return false end
    if xPlayer.addMoney then xPlayer.addMoney(amount, reason or 'HexTactics Crime')
    else xPlayer.addAccountMoney('money', amount, reason or 'HexTactics Crime') end
    return true
end

function HTCrime.CooldownKey(actionType, locationId)
    return ('%s:%s'):format(tostring(actionType), tostring(locationId or 'global'))
end

function HTCrime.CooldownRemaining(key)
    local availableAt = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(`available_at`) FROM `ht_crime_cooldowns` WHERE `action_key`=? LIMIT 1', { key })
    local remaining = (tonumber(availableAt) or 0) - os.time()
    return math.max(0, remaining)
end

function HTCrime.SetCooldown(key, seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds <= 0 then return end
    MySQL.prepare.await([[
        INSERT INTO `ht_crime_cooldowns` (`action_key`,`available_at`) VALUES (?,DATE_ADD(NOW(),INTERVAL ? SECOND))
        ON DUPLICATE KEY UPDATE `available_at`=VALUES(`available_at`)
    ]], { key, seconds })
end

function HTCrime.Token()
    return ('%08x%08x%08x'):format(math.random(0, 0x7fffffff), GetGameTimer() % 0x7fffffff, math.random(0, 0x7fffffff))
end

function HTCrime.CreateSession(source, data)
    local token = HTCrime.Token()
    data.source = source
    data.token = token
    data.startedAt = os.time()
    data.expiresAt = os.time() + math.max(30, tonumber(Config.sessionExpirySeconds) or 300)
    HTCrime.Sessions[token] = data
    return token
end

function HTCrime.GetSession(source, token, expectedType)
    if type(token) ~= 'string' then return nil, 'Ongeldige sessie.' end
    local session = HTCrime.Sessions[token]
    if not session or session.source ~= source then return nil, 'Sessie bestaat niet.' end
    if os.time() > session.expiresAt then HTCrime.Sessions[token] = nil return nil, 'Sessie is verlopen.' end
    if expectedType and session.actionType ~= expectedType then return nil, 'Verkeerde sessie.' end
    return session
end

function HTCrime.EndSession(token)
    HTCrime.Sessions[token] = nil
end

function HTCrime.Audit(source, action, result, metadata)
    local xPlayer = HTCrime.GetPlayer(source)
    local identifier = HTCrime.Identifier(xPlayer) or ('source:%s'):format(source)
    MySQL.insert('INSERT INTO `ht_crime_audit` (`identifier`,`source_id`,`action`,`result`,`metadata`) VALUES (?,?,?,?,?)', {
        identifier, source, tostring(action), tostring(result), json.encode(metadata or {})
    })
end

function HTCrime.Fingerprint(identifier)
    local hash = GetHashKey(('%s:%s'):format(identifier or 'unknown', GetConvar('sv_licenseKey', 'hextactics')))
    return ('HT-%08X'):format(hash & 0xffffffff)
end

function HTCrime.LeaveEvidence(source, evidenceType, location, metadata, chanceOverride)
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or type(location) ~= 'table' then return false end
    local chance = tonumber(chanceOverride) or tonumber(Config.evidenceChance) or 35
    if HTCrime.InventoryCount(source, 'crime_gloves') > 0 then
        chance = math.max(0, chance - (tonumber(Config.glovesEvidenceReduction) or 25))
    end
    if math.random(1, 100) > chance then return false end
    local identifier = HTCrime.Identifier(xPlayer)
    MySQL.insert('INSERT INTO `ht_crime_evidence` (`evidence_type`,`x`,`y`,`z`,`fingerprint`,`metadata`) VALUES (?,?,?,?,?,?)', {
        tostring(evidenceType), tonumber(location.x), tonumber(location.y), tonumber(location.z), HTCrime.Fingerprint(identifier), json.encode(metadata or {})
    })
    return true
end

function HTCrime.Dispatch(source, code, message, location, severity)
    if type(location) ~= 'table' then return end
    local payload = {
        code = tostring(code or 'CRIME'),
        message = tostring(message or 'Verdachte situatie'),
        x = tonumber(location.x), y = tonumber(location.y), z = tonumber(location.z),
        severity = math.floor(tonumber(severity) or 1),
        duration = tonumber(Config.dispatch and Config.dispatch.durationSeconds) or 90,
        radius = tonumber(Config.dispatch and Config.dispatch.radius) or 70.0
    }
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if HTCrime.IsPolice(xPlayer) then
            TriggerClientEvent('htcrime:client:dispatch', xPlayer.source, payload)
        end
    end
    HTCrime.Audit(source, 'dispatch', 'sent', payload)
end

function HTCrime.RandomLocation(actionType)
    local list = Config.locations and Config.locations[actionType]
    if type(list) ~= 'table' or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

function HTCrime.PublicState(source)
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer then return {} end
    local identifier = HTCrime.Identifier(xPlayer)
    local profile = HTCrime.Profile(identifier)
    local gang
    if profile.gang_id then
        gang = MySQL.single.await('SELECT `id`,`name`,`tag`,`reputation`,`color` FROM `ht_crime_gangs` WHERE `id`=? LIMIT 1', { profile.gang_id })
    end
    local jail = MySQL.single.await('SELECT GREATEST(0,UNIX_TIMESTAMP(`release_at`)-UNIX_TIMESTAMP()) AS `remaining`,`reason` FROM `ht_crime_jail` WHERE `identifier`=? AND `release_at`>NOW() LIMIT 1', { identifier })
    return {
        reputation = tonumber(profile.reputation) or 0,
        heat = tonumber(profile.heat) or 0,
        gang = gang,
        jailed = jail and tonumber(jail.remaining) > 0 or false,
        jailRemaining = jail and tonumber(jail.remaining) or 0,
        jailReason = jail and jail.reason or nil,
        police = HTCrime.PoliceCount(),
        blackmarket = HTCrime.CurrentBlackmarket and HTCrime.CurrentBlackmarket() or nil,
        boost = HTCrime.BoostContracts[source]
    }
end

RegisterNetEvent('htcrime:server:requestState', function()
    local source = source
    if HTCrime.Limited(source, 'state', 500) then return end
    TriggerClientEvent('htcrime:client:state', source, HTCrime.PublicState(source))
end)

RegisterNetEvent('htcrime:server:requestEvidence', function()
    local source = source
    if HTCrime.Limited(source, 'evidence', 1500) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.IsPolice(xPlayer) then return end
    local coords = HTCrime.PlayerCoords(source)
    if not coords then return end
    local candidates = MySQL.query.await([[
        SELECT `id`,`evidence_type`,`x`,`y`,`z`,`fingerprint`,`created_at`
        FROM `ht_crime_evidence`
        WHERE `collected`=0 AND `x` BETWEEN ? AND ? AND `y` BETWEEN ? AND ?
        ORDER BY `created_at` DESC LIMIT 50
    ]], { coords.x - 0.001, coords.x + 0.001, coords.y - 0.001, coords.y + 0.001 }) or {}
    local rows = {}
    for _, row in ipairs(candidates) do
        if #(coords - vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z))) <= 35.0 then
            rows[#rows + 1] = row
            if #rows >= 20 then break end
        end
    end
    TriggerClientEvent('htcrime:client:evidenceList', source, rows)
end)

RegisterNetEvent('htcrime:server:collectEvidence', function(evidenceId)
    local source = source
    if HTCrime.Limited(source, 'collectEvidence', 1200) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    evidenceId = tonumber(evidenceId)
    if not evidenceId or not HTCrime.IsPolice(xPlayer) then return end
    if HTCrime.InventoryCount(source, 'evidence_bag') < 1 then return HTCrime.Notify(source, 'Je hebt een bewijszak nodig.', 'error') end
    local row = MySQL.single.await('SELECT * FROM `ht_crime_evidence` WHERE `id`=? AND `collected`=0 LIMIT 1', { evidenceId })
    if not row or not HTCrime.Near(source, row, 4.0) then return end
    if not HTCrime.RemoveItem(source, 'evidence_bag', 1) then return end
    local metadata = { evidenceId=evidenceId, type=row.evidence_type, fingerprint=row.fingerprint, foundAt=row.created_at }
    if not HTCrime.AddItem(source, 'sealed_evidence', 1, metadata) then
        HTCrime.AddItem(source, 'evidence_bag', 1)
        return HTCrime.Notify(source, 'Je inventaris is vol.', 'error')
    end
    MySQL.update.await('UPDATE `ht_crime_evidence` SET `collected`=1,`collected_by`=?,`collected_at`=NOW() WHERE `id`=? AND `collected`=0', { HTCrime.Identifier(xPlayer), evidenceId })
    HTCrime.Notify(source, 'Bewijs veiliggesteld.', 'success')
end)

RegisterCommand('crimekit', function(source)
    if source == 0 then return end
    if HTCrime.Limited(source, 'crimekit', 60000) then return HTCrime.Notify(source, 'Wacht even voordat je opnieuw materiaal pakt.', 'error') end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.IsPolice(xPlayer) and not IsPlayerAceAllowed(source, 'hextactics.admin') then return end
    local supplied = {}
    for item, amount in pairs({ evidence_bag=5, crime_gloves=2 }) do
        if HTCrime.AddItem(source, item, amount, { issuedBy='HexTactics Politie' }) then supplied[#supplied+1] = ('%dx %s'):format(amount, item) end
    end
    HTCrime.Audit(source, 'police_crimekit', 'issued', { items=supplied })
    HTCrime.Notify(source, 'Bewijsuitrusting uitgegeven.', 'success')
end, false)

RegisterCommand('crimeprofile', function(source, args)
    if source == 0 then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.IsPolice(xPlayer) and not IsPlayerAceAllowed(source, 'hextactics.admin') then return end
    local target = HTCrime.GetPlayer(tonumber(args[1]))
    if not target then return HTCrime.Notify(source, 'Speler niet gevonden.', 'error') end
    local profile = HTCrime.Profile(HTCrime.Identifier(target))
    HTCrime.Notify(source, ('Profiel %s | reputatie %d | heat %d'):format(HTCrime.PlayerName(target), profile.reputation or 0, profile.heat or 0), 'info')
end, false)

AddEventHandler('playerDropped', function()
    local source = source
    HTCrime.RateLimits[source] = nil
    HTCrime.BoostContracts[source] = nil
    for token, session in pairs(HTCrime.Sessions) do
        if session.source == source then HTCrime.Sessions[token] = nil end
    end
end)

CreateThread(function()
    while true do
        Wait(3600000)
        MySQL.update('UPDATE `ht_crime_profiles` SET `heat`=GREATEST(0,`heat`-?) WHERE `heat`>0', { math.max(1, tonumber(Config.heatDecayPerHour) or 5) })
        MySQL.update('DELETE FROM `ht_crime_cooldowns` WHERE `available_at` < DATE_SUB(NOW(), INTERVAL 1 DAY)')
        MySQL.update('DELETE FROM `ht_crime_evidence` WHERE `created_at` < DATE_SUB(NOW(), INTERVAL 14 DAY)')
        MySQL.update('DELETE FROM `ht_crime_cloned_plates` WHERE `expires_at` < NOW()')
    end
end)

exports('GetProfile', function(identifier) return HTCrime.Profile(identifier) end)
exports('AddHeat', function(identifier, amount) HTCrime.ChangeProfile(identifier, 0, amount) end)
exports('AddReputation', function(identifier, amount) HTCrime.ChangeProfile(identifier, amount, 0) end)
exports('PoliceCount', HTCrime.PoliceCount)
