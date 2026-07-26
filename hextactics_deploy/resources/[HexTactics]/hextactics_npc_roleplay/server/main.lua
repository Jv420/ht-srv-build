local ESX = exports['es_extended']:getSharedObject()
local resourceName = GetCurrentResourceName()

local function loadConfig()
    local raw = LoadResourceFile(resourceName, 'config.json')
    local ok, decoded = pcall(json.decode, raw or '{}')
    if not ok or type(decoded) ~= 'table' then
        error('[hextactics_npc_roleplay] config.json kon niet worden gelezen.')
    end
    return decoded
end

local Config = loadConfig()
local sessions = {}
local profiles = {}
local cooldowns = {}

local firstNamesMale = { 'Daan', 'Sem', 'Lars', 'Milan', 'Jesse', 'Thijs', 'Bram', 'Niels', 'Sven', 'Kevin', 'Ruben', 'Jeroen' }
local firstNamesFemale = { 'Sophie', 'Emma', 'Lisa', 'Julia', 'Fleur', 'Noa', 'Iris', 'Sanne', 'Anouk', 'Linda', 'Naomi', 'Kim' }
local surnames = { 'De Vries', 'Jansen', 'Visser', 'Smit', 'Bakker', 'Mulder', 'De Boer', 'Bos', 'Vos', 'Meijer', 'Dekker', 'Dijkstra' }
local streets = { 'Waterstraat', 'Havenweg', 'Farmsumerweg', 'Kustweg', 'Singel', 'Oude Schans', 'Stationsweg', 'Schoolstraat', 'Dijklaan', 'Marktstraat' }
local jobs = { 'magazijnmedewerker', 'chauffeur', 'winkelmedewerker', 'monteur', 'havenarbeider', 'kok', 'schoonmaker', 'werkzoekend', 'administratief medewerker', 'ZZP-klushulp' }
local contrabandPool = { 'zakje wiet', 'zakje cocaïne', 'gestolen telefoon', 'inbrekerswerktuig', 'ongeregistreerd mes', 'vuurwapen', 'vals identiteitsbewijs' }

local function debugPrint(...)
    if Config.debug then print('[hextactics_npc_roleplay]', ...) end
end

local function randomChoice(list)
    return list[math.random(1, #list)]
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function getIdentifier(xPlayer)
    if not xPlayer then return nil end
    if type(xPlayer.getIdentifier) == 'function' then
        local ok, identifier = pcall(xPlayer.getIdentifier)
        if ok and identifier and identifier ~= '' then return identifier end
    end
    return xPlayer.identifier
end

local function officerAllowed(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not xPlayer.job then return nil end

    local minimumGrade = Config.policeJobs[xPlayer.job.name]
    if minimumGrade == nil or tonumber(xPlayer.job.grade or 0) < tonumber(minimumGrade) then
        return nil
    end

    if Config.requireDuty then
        local playerState = Player(source).state
        local duty = xPlayer.job.onDuty
        if duty == nil then duty = playerState.onduty end
        if duty == nil then duty = playerState.onDuty end
        if duty == nil then duty = playerState.duty end
        if duty ~= true then return nil end
    end

    return xPlayer
end

local function isRateLimited(source, key)
    local now = GetGameTimer()
    local playerCooldowns = cooldowns[source] or {}
    cooldowns[source] = playerCooldowns
    local last = playerCooldowns[key] or 0
    if now - last < tonumber(Config.requestCooldownMs or 1000) then return true end
    playerCooldowns[key] = now
    return false
end

local function getNetworkEntity(netId, expectedType)
    netId = tonumber(netId)
    if not netId then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    if expectedType and GetEntityType(entity) ~= expectedType then return 0 end
    return entity
end

local function validateDistance(source, entity, maximumDistance)
    local playerPed = GetPlayerPed(source)
    if playerPed == 0 or entity == 0 then return false end
    return #(GetEntityCoords(playerPed) - GetEntityCoords(entity)) <= tonumber(maximumDistance)
end

local function validateNpc(source, netId, maximumDistance)
    local ped = getNetworkEntity(netId, 1)
    if ped == 0 or not validateDistance(source, ped, maximumDistance) then return 0 end
    if IsPedAPlayer and IsPedAPlayer(ped) then return 0 end
    if GetEntityHealth(ped) <= 0 then return 0 end
    return ped
end

local function makeToken(source, netId)
    return ('%s:%s:%s:%s'):format(source, netId, os.time(), math.random(100000, 999999))
end

local function dateOfBirth(age)
    local year = tonumber(os.date('%Y')) - age
    return ('%02d-%02d-%04d'):format(math.random(1, 28), math.random(1, 12), year)
end

local function addViolation(profile, code)
    if not Config.ticketCatalog[code] then return end
    for _, existing in ipairs(profile.violations) do
        if existing == code then return end
    end
    profile.violations[#profile.violations + 1] = code
end

local function createProfile(netId, ped, vehicleNetId)
    local model = GetEntityModel(ped)
    local gender = math.random(1, 100) <= 48 and 'female' or 'male'
    local firstName = randomChoice(gender == 'female' and firstNamesFemale or firstNamesMale)
    local age = math.random(18, 77)
    local licenseRoll = math.random(1, 100)
    local licenseStatus = licenseRoll <= 9 and 'none' or (licenseRoll <= 20 and 'expired' or 'valid')
    local alcohol = math.random(0, 100) <= 19 and (math.random(20, 185) / 100) or 0.0
    local drugs = math.random(1, 100) <= 11
    local wanted = math.random(1, 100) <= 8
    local aggression = math.random(0, 100)
    local profile = {
        key = tostring(netId),
        model = model,
        gender = gender,
        identity = {
            firstName = firstName,
            lastName = randomChoice(surnames),
            age = age,
            dateOfBirth = dateOfBirth(age),
            address = ('%s %s, Delfzijl'):format(randomChoice(streets), math.random(1, 180)),
            occupation = randomChoice(jobs),
            idValid = math.random(1, 100) > 7
        },
        license = {
            status = licenseStatus,
            categories = licenseStatus == 'valid' and { 'B' } or {},
            points = math.random(0, 8)
        },
        alcohol = alcohol,
        drugs = drugs,
        wanted = wanted,
        warrants = wanted and math.random(1, 3) or 0,
        aggression = aggression,
        cooperation = 100 - aggression,
        contraband = {},
        violations = {},
        warned = false,
        arrested = false,
        escorted = false,
        fines = 0,
        vehicleNetId = tonumber(vehicleNetId) or 0,
        vehicleData = nil,
        createdAt = os.time(),
        expiresAt = os.time() + ((tonumber(Config.profileMinutes) or 30) * 60)
    }

    if not profile.identity.idValid then addViolation(profile, 'S001') end
    if licenseStatus ~= 'valid' and profile.vehicleNetId > 0 then addViolation(profile, 'V001') end
    if alcohol >= 0.5 and profile.vehicleNetId > 0 then addViolation(profile, 'V005') end
    if alcohol >= 1.0 and profile.vehicleNetId == 0 then addViolation(profile, 'P005') end

    local contrabandChance = math.random(1, 100)
    if contrabandChance <= 25 then
        profile.contraband[#profile.contraband + 1] = randomChoice(contrabandPool)
        if contrabandChance <= 8 then
            profile.contraband[#profile.contraband + 1] = randomChoice(contrabandPool)
        end
    end

    for _, item in ipairs(profile.contraband) do
        if item == 'zakje wiet' then addViolation(profile, 'P001') end
        if item == 'zakje cocaïne' then addViolation(profile, 'P002') end
        if item == 'vuurwapen' or item == 'ongeregistreerd mes' then addViolation(profile, 'P003') end
    end

    profiles[tostring(netId)] = profile
    return profile
end

local function ensureNpcVehicleData(profile)
    if profile.vehicleNetId <= 0 then return nil end
    if profile.vehicleData then return profile.vehicleData end

    profile.vehicleData = {
        insuranceValid = math.random(1, 100) > 14,
        apkValid = math.random(1, 100) > 12,
        taxValid = math.random(1, 100) > 10,
        possibleStolenHit = profile.wanted and math.random(1, 100) <= 30
    }

    if not profile.vehicleData.insuranceValid then addViolation(profile, 'V002') end
    if not profile.vehicleData.apkValid then addViolation(profile, 'V003') end
    if not profile.vehicleData.taxValid then addViolation(profile, 'V004') end
    return profile.vehicleData
end

local function getProfile(netId, ped, vehicleNetId)
    local key = tostring(netId)
    local profile = profiles[key]
    if not profile or profile.expiresAt < os.time() or profile.model ~= GetEntityModel(ped) then
        profile = createProfile(netId, ped, vehicleNetId)
    elseif tonumber(vehicleNetId) and tonumber(vehicleNetId) > 0 then
        local newVehicleNetId = tonumber(vehicleNetId)
        if profile.vehicleNetId ~= newVehicleNetId then
            profile.vehicleNetId = newVehicleNetId
            profile.vehicleData = nil
        end
    end
    ensureNpcVehicleData(profile)
    return profile
end

local function profileName(profile)
    return ('%s %s'):format(profile.identity.firstName, profile.identity.lastName)
end

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `hextactics_npc_cases` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `officer_identifier` VARCHAR(100) NOT NULL,
            `officer_name` VARCHAR(100) NULL,
            `npc_name` VARCHAR(100) NOT NULL,
            `npc_profile` LONGTEXT NULL,
            `action_type` VARCHAR(50) NOT NULL,
            `action_details` LONGTEXT NULL,
            `fine_amount` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_npc_cases_officer` (`officer_identifier`),
            KEY `idx_npc_cases_action` (`action_type`),
            KEY `idx_npc_cases_created` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

local function logCase(source, xPlayer, profile, actionType, details, fineAmount)
    MySQL.insert.await([[
        INSERT INTO `hextactics_npc_cases`
            (officer_identifier, officer_name, npc_name, npc_profile, action_type, action_details, fine_amount)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        getIdentifier(xPlayer),
        GetPlayerName(source),
        profileName(profile),
        json.encode({
            gender = profile.gender,
            dateOfBirth = profile.identity.dateOfBirth,
            address = profile.identity.address,
            occupation = profile.identity.occupation,
            license = profile.license,
            violations = profile.violations,
            wanted = profile.wanted,
            warrants = profile.warrants
        }),
        tostring(actionType):sub(1, 50),
        json.encode(type(details) == 'table' and details or { value = details }),
        math.max(0, math.floor(tonumber(fineAmount) or 0))
    })
end

local function ticketCatalogForClient()
    local list = {}
    for code, ticket in pairs(Config.ticketCatalog) do
        list[#list + 1] = {
            code = code,
            label = ticket.label,
            amount = tonumber(ticket.amount) or 0,
            arrestable = ticket.arrestable == true
        }
    end
    table.sort(list, function(left, right) return left.code < right.code end)
    return list
end

local function validateSession(source, token)
    local session = sessions[source]
    if not session or session.token ~= tostring(token or '') or session.expiresAt < os.time() then
        sessions[source] = nil
        return nil, nil, nil
    end

    local xPlayer = officerAllowed(source)
    if not xPlayer then return nil, nil, nil end
    local ped = validateNpc(source, session.netId, Config.sessionDistance)
    if ped == 0 then return nil, nil, nil end
    local profile = profiles[tostring(session.netId)]
    if not profile then return nil, nil, nil end
    return session, profile, xPlayer
end

local function hasArrestGrounds(profile)
    if profile.wanted or profile.warrants > 0 then return true, 'Openstaand arrestatiebevel' end
    if profile.alcohol >= 1.3 and profile.vehicleNetId > 0 then return true, 'Ernstig rijden onder invloed' end
    for _, code in ipairs(profile.violations) do
        local ticket = Config.ticketCatalog[code]
        if ticket and ticket.arrestable then return true, ticket.label end
    end
    return false, nil
end

local function maybeReaction(profile, action)
    if profile.arrested then return nil end
    local chance = 0
    if profile.wanted then chance = chance + 35 end
    if action == 'frisk' then chance = chance + math.floor(profile.aggression * 0.25) end
    if action == 'identity' or action == 'license' then chance = chance + math.floor(profile.aggression * 0.08) end
    if math.random(1, 100) <= chance then return 'flee' end
    return nil
end

RegisterNetEvent('hextactics_npc:requestOpen', function(netId, vehicleNetId)
    local source = source
    if isRateLimited(source, 'open') then return end
    local xPlayer = officerAllowed(source)
    if not xPlayer then
        TriggerClientEvent('hextactics_npc:notify', source, 'Je bent niet bevoegd om deze politiecontrole uit te voeren.')
        return
    end

    local ped = validateNpc(source, netId, Config.interactionDistance)
    if ped == 0 then return end

    local validVehicleNetId = 0
    local vehicle = getNetworkEntity(vehicleNetId, 2)
    if vehicle ~= 0 and validateDistance(source, vehicle, Config.sessionDistance) then
        if GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped then
            validVehicleNetId = tonumber(vehicleNetId)
        end
    end

    local profile = getProfile(netId, ped, validVehicleNetId)
    local token = makeToken(source, netId)
    sessions[source] = {
        token = token,
        netId = tonumber(netId),
        vehicleNetId = validVehicleNetId,
        expiresAt = os.time() + (tonumber(Config.sessionSeconds) or 180)
    }

    TriggerClientEvent('hextactics_npc:openMenu', source, {
        token = token,
        netId = tonumber(netId),
        title = 'NPC politiecontrole',
        subtitle = 'Identiteit nog niet vastgesteld',
        arrested = profile.arrested,
        escorted = profile.escorted,
        tickets = ticketCatalogForClient()
    })
end)

RegisterNetEvent('hextactics_npc:performAction', function(token, action, payload)
    local source = source
    if isRateLimited(source, 'action') then return end
    action = type(action) == 'string' and action:sub(1, 30) or ''
    payload = type(payload) == 'table' and payload or {}

    local session, profile, xPlayer = validateSession(source, token)
    if not session then
        TriggerClientEvent('hextactics_npc:actionResult', source, { close = true, message = 'De controlesessie is verlopen.' })
        return
    end

    local result = { action = action, arrested = profile.arrested, escorted = profile.escorted }

    if action == 'identity' then
        result.title = 'Identiteitscontrole'
        result.lines = {
            ('Naam: %s'):format(profileName(profile)),
            ('Geboortedatum: %s'):format(profile.identity.dateOfBirth),
            ('Adres: %s'):format(profile.identity.address),
            ('Beroep: %s'):format(profile.identity.occupation),
            ('Identiteitsbewijs: %s'):format(profile.identity.idValid and 'geldig' or 'ongeldig/ontbreekt')
        }
        result.subtitle = profileName(profile)
        result.behavior = maybeReaction(profile, action)
        logCase(source, xPlayer, profile, action, { valid = profile.identity.idValid }, 0)

    elseif action == 'license' then
        local statusLabels = { valid = 'geldig', expired = 'verlopen', none = 'geen rijbewijs' }
        result.title = 'Rijbewijscontrole'
        result.lines = {
            ('Status: %s'):format(statusLabels[profile.license.status] or profile.license.status),
            ('Categorieën: %s'):format(#profile.license.categories > 0 and table.concat(profile.license.categories, ', ') or 'geen'),
            ('Strafpunten: %s'):format(profile.license.points)
        }
        result.behavior = maybeReaction(profile, action)
        logCase(source, xPlayer, profile, action, profile.license, 0)

    elseif action == 'breathalyzer' then
        result.title = 'Alcohol- en drugstest'
        result.lines = {
            ('Alcohol: %.2f ‰'):format(profile.alcohol),
            ('Indicatieve drugstest: %s'):format(profile.drugs and 'POSITIEF' or 'negatief')
        }
        logCase(source, xPlayer, profile, action, { alcohol = profile.alcohol, drugs = profile.drugs }, 0)

    elseif action == 'frisk' then
        result.title = 'Fouillering'
        result.lines = #profile.contraband > 0
            and { ('Aangetroffen: %s'):format(table.concat(profile.contraband, ', ')) }
            or { 'Geen verboden goederen aangetroffen.' }
        result.behavior = maybeReaction(profile, action)
        logCase(source, xPlayer, profile, action, { items = profile.contraband }, 0)

    elseif action == 'vehicle' then
        if session.vehicleNetId == 0 then
            result.title = 'Voertuigcontrole'
            result.lines = { 'De NPC bestuurt momenteel geen controleerbaar voertuig.' }
        else
            local vehicle = getNetworkEntity(session.vehicleNetId, 2)
            if vehicle == 0 then return end
            local plate = GetVehicleNumberPlateText(vehicle)
            local record
            if GetResourceState('ht_rdw') == 'started' then
                local ok, value = pcall(function()
                    return exports['ht_rdw']:GetPublicVehicleRecord(plate)
                end)
                if ok then record = value end
            end

            if record then
                result.title = ('Voertuigcontrole — %s'):format(record.plate)
                result.lines = {
                    ('VIN: %s'):format(record.vin),
                    ('Registratie: %s'):format(record.status or 'active'),
                    ('Gestolen: %s'):format(record.stolen and 'JA' or 'nee'),
                    ('APK: %s'):format(record.apkValid and 'geldig' or 'VERLOPEN'),
                    ('Verzekering: %s'):format(record.insuranceValid and 'geldig' or 'ONTBREEKT/VERLOPEN'),
                    ('Belasting: %s'):format(record.taxValid and 'geldig' or 'VERLOPEN')
                }
                if not record.insuranceValid then addViolation(profile, 'V002') end
                if not record.apkValid then addViolation(profile, 'V003') end
                if not record.taxValid then addViolation(profile, 'V004') end
            else
                local vehicleData = ensureNpcVehicleData(profile)
                result.title = ('NPC-voertuigcontrole — %s'):format(plate)
                result.lines = {
                    'Eigenaar: ' .. profileName(profile),
                    ('Gestolen: %s'):format(vehicleData.possibleStolenHit and 'MOGELIJKE HIT' or 'nee'),
                    ('APK: %s'):format(vehicleData.apkValid and 'geldig' or 'VERLOPEN'),
                    ('Verzekering: %s'):format(vehicleData.insuranceValid and 'geldig' or 'ONTBREEKT/VERLOPEN'),
                    ('Belasting: %s'):format(vehicleData.taxValid and 'geldig' or 'VERLOPEN')
                }
            end
            logCase(source, xPlayer, profile, action, { plate = plate }, 0)
        end

    elseif action == 'wanted' then
        result.title = 'Signaleringen'
        result.lines = profile.wanted
            and { ('HIT: %s openstaande signalering(en).'):format(profile.warrants) }
            or { 'Geen actieve signaleringen.' }
        logCase(source, xPlayer, profile, action, { wanted = profile.wanted, warrants = profile.warrants }, 0)

    elseif action == 'warn' then
        profile.warned = true
        result.title = 'Waarschuwing geregistreerd'
        result.lines = { 'De NPC heeft een officiële waarschuwing gekregen.' }
        result.behavior = 'comply'
        logCase(source, xPlayer, profile, action, { warning = true }, 0)

    elseif action == 'ticket' then
        local code = type(payload.code) == 'string' and payload.code:sub(1, 10) or ''
        local ticket = Config.ticketCatalog[code]
        if not ticket then return end
        local amount = math.max(0, math.floor(tonumber(ticket.amount) or 0))
        profile.fines = profile.fines + amount
        result.title = 'Boete uitgeschreven'
        result.lines = {
            ('Feitcode: %s'):format(code),
            ('Overtreding: %s'):format(ticket.label),
            ('Bedrag: €%s'):format(amount),
            ('Totaal NPC-dossier: €%s'):format(profile.fines)
        }
        result.behavior = profile.aggression >= 85 and 'argue' or 'comply'
        logCase(source, xPlayer, profile, action, { code = code, label = ticket.label }, amount)

    elseif action == 'arrest' then
        local allowed, reason = hasArrestGrounds(profile)
        if not allowed then
            result.title = 'Aanhouding geweigerd'
            result.lines = { 'De server vindt op dit moment geen geldige aanhoudingsgrond in het NPC-dossier.' }
        else
            profile.arrested = true
            profile.escorted = false
            result.arrested = true
            result.escorted = false
            result.title = 'NPC aangehouden'
            result.lines = { ('Aanhoudingsgrond: %s'):format(reason) }
            result.behavior = profile.aggression >= 70 and 'resist' or 'handsup'
            logCase(source, xPlayer, profile, action, { reason = reason }, 0)
        end

    elseif action == 'escort' then
        if not profile.arrested then return end
        profile.escorted = not profile.escorted
        result.arrested = true
        result.escorted = profile.escorted
        result.title = profile.escorted and 'Escort gestart' or 'Escort gestopt'
        result.lines = { profile.escorted and 'De NPC volgt de agent.' or 'De NPC blijft op de plaats.' }
        result.behavior = profile.escorted and 'escort' or 'handsup'
        logCase(source, xPlayer, profile, action, { escorted = profile.escorted }, 0)

    elseif action == 'release' then
        profile.arrested = false
        profile.escorted = false
        result.arrested = false
        result.escorted = false
        result.title = 'NPC vrijgelaten'
        result.lines = { 'De controlesessie is afgerond en de NPC mag vertrekken.' }
        result.behavior = 'release'
        result.close = true
        logCase(source, xPlayer, profile, action, { released = true }, 0)

    else
        return
    end

    TriggerClientEvent('hextactics_npc:actionResult', source, result)
end)

RegisterNetEvent('hextactics_npc:closeSession', function(token)
    local source = source
    local session = sessions[source]
    if session and session.token == tostring(token or '') then sessions[source] = nil end
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    cooldowns[source] = nil
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for source, session in pairs(sessions) do
            if session.expiresAt < now then sessions[source] = nil end
        end
        for key, profile in pairs(profiles) do
            if profile.expiresAt < now then profiles[key] = nil end
        end
    end
end)

MySQL.ready(function()
    createTables()
    print('[hextactics_npc_roleplay] Beveiligde NPC-roleplay gestart. ALT + E bij een NPC.')
end)
